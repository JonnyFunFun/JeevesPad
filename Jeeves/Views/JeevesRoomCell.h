#import <UIKit/UIKit.h>

@class JeevesRoom;
@class JeevesRoomCell;
@class HAEntity;

@protocol JeevesRoomCellDelegate <NSObject>

- (void)roomCell:(JeevesRoomCell *)cell didToggleAllForRoom:(JeevesRoom *)room toState:(BOOL)on;

@end

@interface JeevesRoomCell : UICollectionViewCell

@property (nonatomic, weak) id<JeevesRoomCellDelegate> delegate;
@property (nonatomic, strong) JeevesRoom *room;

- (void)configureWithRoom:(JeevesRoom *)room lights:(NSArray<HAEntity *> *)lights;

@end
