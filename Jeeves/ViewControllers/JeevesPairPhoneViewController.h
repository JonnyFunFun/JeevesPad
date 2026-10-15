#import <UIKit/UIKit.h>

@class JeevesRegisteredPhone;

// Registers a phone with Home Assistant by pairing it with this iPad (JeevesPhonePairer)
@interface JeevesPairPhoneViewController : UITableViewController

// Called after the phone has been registered
@property (nonatomic, copy) void (^onRegistered)(JeevesRegisteredPhone *phone);

@end
