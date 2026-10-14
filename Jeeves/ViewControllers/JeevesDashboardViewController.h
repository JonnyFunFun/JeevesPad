#import <UIKit/UIKit.h>

@interface JeevesDashboardViewController : UIViewController

// Switches to the Home dashboard (e.g. after the idle timeout)
- (void)showHome;

// Stops timers and observers so the dashboard can be released (before it's replaced)
- (void)stopUpdates;

@end
