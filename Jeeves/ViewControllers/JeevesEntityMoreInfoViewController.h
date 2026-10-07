#import <UIKit/UIKit.h>

@class HAEntity;

// Detail view for a single entity, opened by long-pressing an entity card
// (the equivalent of Home Assistant's "more info" dialog). Shows the state,
// type-specific controls and the entity's attributes, refreshing while open.
@interface JeevesEntityMoreInfoViewController : UIViewController

// dashboardID identifies the card that was opened (see JeevesCardSettings); when
// set, a "Card" section lets the user rename and resize that card. May be nil.
- (instancetype)initWithEntity:(HAEntity *)entity dashboardID:(NSString *)dashboardID;

@end
