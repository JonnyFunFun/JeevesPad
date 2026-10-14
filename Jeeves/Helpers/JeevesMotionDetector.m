#import "JeevesMotionDetector.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>

// Luminance is sampled on a coarse grid; motion = enough cells changing between frames
static const int kGridWidth = 32;
static const int kGridHeight = 24;
static const int kCellChangeThreshold = 22;         // luma difference (0-255) that counts as a change
static const double kChangedFractionThreshold = 0.04; // share of cells that must change
static const NSInteger kConsecutiveFramesRequired = 2; // filters out single-frame noise
static const NSInteger kWarmupFrames = 6;             // let auto-exposure settle after starting
static const CFTimeInterval kMinFrameInterval = 0.25; // analyze at most ~4 frames per second

@interface JeevesMotionDetector () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) dispatch_queue_t videoQueue;
@property (nonatomic, strong) AVCaptureSession *session;
// Accessed only on videoQueue
@property (nonatomic, assign) BOOL hasPrevious;
@property (nonatomic, assign) NSInteger framesSeen;
@property (nonatomic, assign) NSInteger consecutiveMotionFrames;
@property (nonatomic, assign) CFTimeInterval lastFrameTime;
@end

@implementation JeevesMotionDetector {
    int16_t _previous[kGridWidth * kGridHeight]; // previous frame, relative to its mean
}

+ (AVCaptureDevice *)frontCamera {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == AVCaptureDevicePositionFront) return device;
    }
    return nil;
}

+ (BOOL)isAvailable {
    return [self frontCamera] != nil;
}

+ (BOOL)isAuthorized {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized;
}

+ (void)requestAccessWithCompletion:(void (^)(BOOL))completion {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(granted);
        });
    }];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionQueue = dispatch_queue_create("jeeves.motion.session", DISPATCH_QUEUE_SERIAL);
        _videoQueue = dispatch_queue_create("jeeves.motion.video", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    AVCaptureSession *session = _session;
    dispatch_async(_sessionQueue, ^{
        [session stopRunning];
    });
}

- (void)start {
    if (![[self class] isAuthorized]) return;
    dispatch_async(self.sessionQueue, ^{
        if (self.session.isRunning) return;
        if (!self.session) [self configureSession];
        dispatch_sync(self.videoQueue, ^{
            self.hasPrevious = NO;
            self.framesSeen = 0;
            self.consecutiveMotionFrames = 0;
        });
        [self.session startRunning];
    });
}

- (void)stop {
    dispatch_async(self.sessionQueue, ^{
        [self.session stopRunning];
    });
}

// Runs on sessionQueue
- (void)configureSession {
    AVCaptureDevice *camera = [[self class] frontCamera];
    NSError *error = nil;
    AVCaptureDeviceInput *input = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
    if (!input) {
        NSLog(@"[MotionDetector] No front camera input: %@", error);
        return;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];
    if ([session canSetSessionPreset:AVCaptureSessionPresetLow]) session.sessionPreset = AVCaptureSessionPresetLow;
    if ([session canAddInput:input]) [session addInput:input];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.videoSettings = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    output.alwaysDiscardsLateVideoFrames = YES;
    [output setSampleBufferDelegate:self queue:self.videoQueue];
    if ([session canAddOutput:output]) [session addOutput:output];
    [session commitConfiguration];

    // Lower the frame rate where supported, to save power (frames are also throttled below)
    if ([camera lockForConfiguration:nil]) {
        for (AVFrameRateRange *range in camera.activeFormat.videoSupportedFrameRateRanges) {
            if (range.minFrameRate <= 5 && range.maxFrameRate >= 5) {
                camera.activeVideoMinFrameDuration = CMTimeMake(1, 5);
                camera.activeVideoMaxFrameDuration = CMTimeMake(1, 5);
                break;
            }
        }
        [camera unlockForConfiguration];
    }
    self.session = session;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastFrameTime < kMinFrameInterval) return;
    self.lastFrameTime = now;

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer || CVPixelBufferGetPlaneCount(pixelBuffer) < 1) return;

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    const uint8_t *luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);

    int16_t current[kGridWidth * kGridHeight];
    long sum = 0;
    if (luma && width >= kGridWidth && height >= kGridHeight) {
        for (int gy = 0; gy < kGridHeight; gy++) {
            size_t y = (gy * height + height / 2) / kGridHeight;
            for (int gx = 0; gx < kGridWidth; gx++) {
                size_t x = (gx * width + width / 2) / kGridWidth;
                current[gy * kGridWidth + gx] = luma[y * bytesPerRow + x];
                sum += current[gy * kGridWidth + gx];
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (!luma || width < kGridWidth || height < kGridHeight) return;

    // Compare relative to each frame's mean, so exposure/lighting shifts don't count as motion
    int16_t mean = (int16_t)(sum / (kGridWidth * kGridHeight));
    for (int i = 0; i < kGridWidth * kGridHeight; i++) current[i] -= mean;

    self.framesSeen++;
    if (self.hasPrevious && self.framesSeen > kWarmupFrames) {
        int changed = 0;
        for (int i = 0; i < kGridWidth * kGridHeight; i++) {
            if (abs(current[i] - _previous[i]) > kCellChangeThreshold) changed++;
        }
        BOOL motion = changed > kChangedFractionThreshold * (kGridWidth * kGridHeight);
        self.consecutiveMotionFrames = motion ? self.consecutiveMotionFrames + 1 : 0;
        if (self.consecutiveMotionFrames >= kConsecutiveFramesRequired) {
            self.consecutiveMotionFrames = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.motionHandler) self.motionHandler();
            });
        }
    }
    memcpy(_previous, current, sizeof(current));
    self.hasPrevious = YES;
}

@end
