#import <UIKit/UIKit.h>

@class JeevesRoom;
@class HAEntity;

@interface JeevesRoomDetailViewController : UIViewController

@property (nonatomic, strong) JeevesRoom *room;
@property (nonatomic, strong) NSArray<HAEntity *> *allEntities;

@end
