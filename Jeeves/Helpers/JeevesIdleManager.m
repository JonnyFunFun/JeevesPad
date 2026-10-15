#import "JeevesIdleManager.h"
#import "JeevesMotionDetector.h"

NSString * const JeevesIdleSettingsDidChangeNotification = @"JeevesIdleSettingsDidChangeNotification";

static NSString * const kDefaultsHomeTimeout    = @"JeevesIdleHomeTimeout";
static NSString * const kDefaultsDimsWhenIdle   = @"JeevesIdleDimsWhenIdle";
static NSString * const kDefaultsWakesOnMotion  = @"JeevesIdleWakesOnMotion";
// Brightness before dimming, persisted so it can be restored if the app is killed while dimmed
static NSString * const kDefaultsSavedBrightness = @"JeevesIdleSavedBrightness";

static const NSTimeInterval kDefaultHomeTimeout = 180;
static const NSTimeInterval kCheckInterval = 2.0;
static const CGFloat kDimmedBrightness = 0.1; // dim, but clearly still on
static const NSInteger kFadeSteps = 10;
static const NSTimeInterval kFadeDuration = 0.8;

@interface JeevesIdleManager ()
@property (nonatomic, assign, readwrite, getter=isDimmed) BOOL dimmed;
@property (nonatomic, strong) NSDate *lastActivity;
@property (nonatomic, assign) BOOL didReturnHome;
@property (nonatomic, assign) CGFloat brightnessBeforeDim;
@property (nonatomic, strong) NSTimer *checkTimer;
@property (nonatomic, strong) JeevesMotionDetector *motionDetector;
@property (nonatomic, assign) NSUInteger fadeGeneration; // cancels an in-progress fade
@end

@implementation JeevesIdleManager

+ (instancetype)sharedManager {
    static JeevesIdleManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadSettings];
        _lastActivity = [NSDate date];
    }
    return self;
}

- (void)loadSettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _homeTimeout = [d objectForKey:kDefaultsHomeTimeout] ? [d doubleForKey:kDefaultsHomeTimeout] : kDefaultHomeTimeout;
    _dimsWhenIdle = [d objectForKey:kDefaultsDimsWhenIdle] ? [d boolForKey:kDefaultsDimsWhenIdle] : YES;
    _wakesOnMotion = [d boolForKey:kDefaultsWakesOnMotion];
}

- (void)reloadFromDefaults {
    [self loadSettings];
    if (!self.dimsWhenIdle) [self undim];
    [self applyIdleTimerSetting];
    [self userDidInteract];
    [self settingsChanged];
}

+ (NSArray<NSNumber *> *)timeoutChoices {
    return @[@0, @60, @120, @180, @300, @600, @900, @1800];
}

+ (NSString *)titleForTimeout:(NSTimeInterval)timeout {
    if (timeout <= 0) return @"Never";
    NSInteger minutes = (NSInteger)round(timeout / 60);
    return minutes == 1 ? @"1 minute" : [NSString stringWithFormat:@"%ld minutes", (long)minutes];
}

#pragma mark - Settings

- (void)settingsChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesIdleSettingsDidChangeNotification object:self];
}

- (void)setHomeTimeout:(NSTimeInterval)homeTimeout {
    _homeTimeout = MAX(0, homeTimeout);
    [[NSUserDefaults standardUserDefaults] setDouble:_homeTimeout forKey:kDefaultsHomeTimeout];
    [self userDidInteract]; // start the new timeout from now
    [self applyIdleTimerSetting];
    [self settingsChanged];
}

- (void)setDimsWhenIdle:(BOOL)dimsWhenIdle {
    _dimsWhenIdle = dimsWhenIdle;
    [[NSUserDefaults standardUserDefaults] setBool:dimsWhenIdle forKey:kDefaultsDimsWhenIdle];
    if (!dimsWhenIdle) [self undim];
    [self applyIdleTimerSetting];
    [self settingsChanged];
}

- (void)setWakesOnMotion:(BOOL)wakesOnMotion {
    _wakesOnMotion = wakesOnMotion;
    [[NSUserDefaults standardUserDefaults] setBool:wakesOnMotion forKey:kDefaultsWakesOnMotion];
    if (wakesOnMotion && self.dimmed) {
        [self.motionDetector start];
    } else if (!wakesOnMotion) {
        [self.motionDetector stop];
    }
    [self settingsChanged];
}

// While dimming is in use, keep iOS from locking the screen: it dims instead
- (void)applyIdleTimerSetting {
    [UIApplication sharedApplication].idleTimerDisabled = (self.dimsWhenIdle && self.homeTimeout > 0);
}

#pragma mark - Lifecycle

- (void)start {
    [self restoreBrightnessAfterInterruption];
    [self applyIdleTimerSetting];
    self.lastActivity = [NSDate date];

    __weak typeof(self) weakSelf = self;
    self.motionDetector = [[JeevesMotionDetector alloc] init];
    self.motionDetector.motionHandler = ^{
        [weakSelf userDidInteract];
    };

    [self.checkTimer invalidate];
    self.checkTimer = [NSTimer timerWithTimeInterval:kCheckInterval target:self selector:@selector(checkIdle) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.checkTimer forMode:NSRunLoopCommonModes];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)appWillResignActive {
    // Never leave the device dimmed outside the app
    [self undimImmediately];
}

- (void)appDidBecomeActive {
    [self restoreBrightnessAfterInterruption];
    [self applyIdleTimerSetting];
    self.lastActivity = [NSDate date];
    self.didReturnHome = NO;
}

// If the app was killed while dimmed, put the brightness back
- (void)restoreBrightnessAfterInterruption {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!self.dimmed && [d objectForKey:kDefaultsSavedBrightness]) {
        [UIScreen mainScreen].brightness = [d doubleForKey:kDefaultsSavedBrightness];
        [d removeObjectForKey:kDefaultsSavedBrightness];
    }
}

#pragma mark - Activity

- (NSTimeInterval)idleTime {
    return self.lastActivity ? -[self.lastActivity timeIntervalSinceNow] : 0;
}

- (void)userDidInteract {
    self.lastActivity = [NSDate date];
    self.didReturnHome = NO;
    if (self.dimmed) [self undim];
}

- (void)checkIdle {
    if (self.homeTimeout <= 0 || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSTimeInterval idle = -[self.lastActivity timeIntervalSinceNow];

    if (!self.didReturnHome && idle >= self.homeTimeout) {
        self.didReturnHome = YES;
        if (self.returnHomeHandler) self.returnHomeHandler();
    }
    if (self.dimsWhenIdle && !self.dimmed && idle >= self.homeTimeout * 2) {
        [self dim];
    }
}

#pragma mark - Brightness

- (void)dim {
    self.dimmed = YES;
    self.brightnessBeforeDim = [UIScreen mainScreen].brightness;
    [[NSUserDefaults standardUserDefaults] setDouble:self.brightnessBeforeDim forKey:kDefaultsSavedBrightness];
    [self fadeBrightnessTo:MIN(kDimmedBrightness, self.brightnessBeforeDim)];
    if (self.wakesOnMotion) [self.motionDetector start];
}

- (void)undim {
    if (!self.dimmed) return;
    self.dimmed = NO;
    [self.motionDetector stop];
    [self fadeBrightnessTo:self.brightnessBeforeDim];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsSavedBrightness];
}

- (void)undimImmediately {
    if (!self.dimmed) return;
    self.dimmed = NO;
    self.fadeGeneration++;
    [self.motionDetector stop];
    [UIScreen mainScreen].brightness = self.brightnessBeforeDim;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsSavedBrightness];
}

- (void)fadeBrightnessTo:(CGFloat)target {
    NSUInteger generation = ++self.fadeGeneration;
    CGFloat start = [UIScreen mainScreen].brightness;
    for (NSInteger step = 1; step <= kFadeSteps; step++) {
        CGFloat value = start + (target - start) * step / kFadeSteps;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFadeDuration * step / kFadeSteps * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation == self.fadeGeneration) [UIScreen mainScreen].brightness = value;
        });
    }
}

@end

#pragma mark - Application

@implementation JeevesApplication {
    BOOL _swallowingWakeTouch;
}

- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        NSSet<UITouch *> *touches = [event allTouches];
        BOOL began = NO, allEnded = YES;
        for (UITouch *touch in touches) {
            if (touch.phase == UITouchPhaseBegan) began = YES;
            if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) allEnded = NO;
        }

        JeevesIdleManager *idle = [JeevesIdleManager sharedManager];
        if (began && idle.isDimmed) {
            // This touch just wakes the screen; don't let it press anything
            _swallowingWakeTouch = YES;
        }
        if (began) [idle userDidInteract];

        if (_swallowingWakeTouch) {
            if (allEnded) _swallowingWakeTouch = NO;
            return;
        }
    }
    [super sendEvent:event];
}

@end
