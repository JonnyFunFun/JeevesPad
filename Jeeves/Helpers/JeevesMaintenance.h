#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Maintenance mode: a full-screen notice over everything (even alerts) that blocks the
// panel until it's turned off, from Home Assistant (the fleet "maintenance" command) or
// at the panel by holding the notice for 5 seconds and entering the unlock code (the
// Guided Access unlock code; without one, only Home Assistant can end it). Kept per
// iPad across restarts.
@interface JeevesMaintenance : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, copy, readonly) NSString *message; // shown on the notice

+ (NSString *)defaultMessage;

- (void)start; // call at launch: shows the notice again if maintenance was on
- (void)setActive:(BOOL)active message:(nullable NSString *)message;

@end

NS_ASSUME_NONNULL_END
