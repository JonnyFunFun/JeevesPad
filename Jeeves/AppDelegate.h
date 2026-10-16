#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

// Commands sent by the JeevesPad Manager app in Home Assistant (JeevesFleetService):
// "home", "reload", "wake", "identify", "brightness" (value 0–1), "guided_access"
// (value true/false; the result shows in the status request), "maintenance" (value
// {on, message}). Returns an error
// message, or nil on success.
- (NSString *)performRemoteCommand:(NSString *)command value:(id)value;

@end
