#import <UIKit/UIKit.h>

@class JeevesRegisteredPhone;

// Registers a phone with Home Assistant from its name and key (IRK)
@interface JeevesAddPhoneViewController : UITableViewController

// Called after the phone has been registered (before this screen closes)
@property (nonatomic, copy) void (^onRegistered)(JeevesRegisteredPhone *phone);

@end
