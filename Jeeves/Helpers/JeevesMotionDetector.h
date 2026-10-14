#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Detects movement in front of the device using the front camera at a very low
// resolution and frame rate (iPads have no proximity sensor). Frames are analyzed
// in memory and never stored or sent anywhere.
@interface JeevesMotionDetector : NSObject

// Called on the main thread when movement is seen
@property (nonatomic, copy, nullable) void (^motionHandler)(void);

+ (BOOL)isAvailable;  // has a front camera
+ (BOOL)isAuthorized; // camera access granted
+ (void)requestAccessWithCompletion:(void (^)(BOOL granted))completion; // completion on main thread

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
