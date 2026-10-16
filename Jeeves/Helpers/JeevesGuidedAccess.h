#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main thread when Guided Access starts or ends, or a request fails
extern NSString * const JeevesGuidedAccessDidChangeNotification;

// Starts and ends Guided Access from Jeeves (iOS's "Autonomous Single App Mode").
// iOS only allows this on a supervised iPad whose configuration profile lists Jeeves
// (com.jeeves.Jeeves) under autonomousSingleAppModePermittedAppIDs; elsewhere requests
// fail and `lastError` says why. A session started this way has no Guided Access
// passcode, so people end it in Jeeves with the unlock code (JeevesGuidedAccessCode, a
// fleet setting). Whether it's wanted is remembered per iPad, and requested again at launch.
@interface JeevesGuidedAccess : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly) BOOL wanted;                 // last requested state, kept across restarts
@property (nonatomic, copy, readonly, nullable) NSString *lastError;
@property (nonatomic, copy, nullable) NSString *unlockCode;  // shared with the fleet; nil/empty = none

- (void)start; // call at launch: watches for changes and restores a wanted session
- (void)setWanted:(BOOL)wanted completion:(nullable void (^)(BOOL success))completion;
- (BOOL)checkUnlockCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
