#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when an idle setting changes
extern NSString * const JeevesIdleSettingsDidChangeNotification;

// Tracks user activity for a wall-panel style setup: after `homeTimeout` without
// input the UI returns to Home, and at twice that the screen dims (never turns off)
// until the next touch, or movement in front of the camera if `wakesOnMotion`.
@interface JeevesIdleManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) NSTimeInterval homeTimeout; // seconds; 0 = never (default 3 minutes)
@property (nonatomic, assign) BOOL dimsWhenIdle;          // default YES; keeps the screen from auto-locking
@property (nonatomic, assign) BOOL wakesOnMotion;         // default NO; uses the front camera while dimmed
@property (nonatomic, assign, readonly, getter=isDimmed) BOOL dimmed;

// Called on the main thread when the home timeout elapses
@property (nonatomic, copy, nullable) void (^returnHomeHandler)(void);

- (void)start;
- (void)userDidInteract;
// Re-reads settings from NSUserDefaults (e.g. after another iPad shared its settings)
- (void)reloadFromDefaults;

+ (NSArray<NSNumber *> *)timeoutChoices;          // seconds, including 0 (never)
+ (NSString *)titleForTimeout:(NSTimeInterval)timeout; // "3 minutes", "Never"

@end

// Application subclass that reports every touch (in any window, including the
// keyboard and alerts) to JeevesIdleManager, and swallows the touch that wakes a
// dimmed screen so it doesn't also press whatever was under it.
@interface JeevesApplication : UIApplication
@end

NS_ASSUME_NONNULL_END
