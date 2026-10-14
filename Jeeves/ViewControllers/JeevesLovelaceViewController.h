#import <UIKit/UIKit.h>
#import "JeevesRefreshable.h"

// Shows a Home Assistant (Lovelace) dashboard natively: its config is fetched over
// the WebSocket API and rebuilt with Jeeves cards, scaled to the screen. The real
// Lovelace UI needs iOS 12+, so it can't be shown in a web view on iOS 9.
@interface JeevesLovelaceViewController : UIViewController <JeevesRefreshable>

@end
