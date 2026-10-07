#import <UIKit/UIKit.h>

@class JeevesRoom;
@class HAEntity;

@interface JeevesAddRoomViewController : UIViewController

@property (nonatomic, strong) JeevesRoom *room; // nil for new room, set for editing
@property (nonatomic, strong) NSArray<HAEntity *> *allEntities;

@end
