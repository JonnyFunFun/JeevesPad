#import <UIKit/UIKit.h>

@class HAEntity;

@class JeevesLightToggleCell;

@protocol JeevesLightToggleCellDelegate <NSObject>
// Entity may be nil if it was deallocated - use cell.entityId for API calls
- (void)lightToggleCell:(JeevesLightToggleCell *)cell didToggleEntity:(HAEntity *)entity toState:(BOOL)on;
- (void)lightToggleCell:(JeevesLightToggleCell *)cell didSetBrightness:(NSInteger)brightness forEntity:(HAEntity *)entity;
@optional
// For scripts - triggers script execution (entity may be nil, use cell.entityId)
- (void)lightToggleCell:(JeevesLightToggleCell *)cell didTriggerScript:(HAEntity *)entity;
// Called when user starts/stops interacting with cell (brightness slider)
- (void)lightToggleCell:(JeevesLightToggleCell *)cell didChangeInteractionState:(BOOL)isInteracting;
// Called when a read-only entity (sensor) is tapped, which can't be toggled
- (void)lightToggleCellDidTapReadOnlyEntity:(JeevesLightToggleCell *)cell;
@end

@interface JeevesLightToggleCell : UICollectionViewCell

@property (nonatomic, weak) id<JeevesLightToggleCellDelegate> delegate;
// Entity is weak - may become nil if the entity is replaced
@property (nonatomic, weak, readonly) HAEntity *entity;
// EntityId is always available - use this for API calls
@property (nonatomic, copy, readonly) NSString *entityId;

- (void)configureWithEntity:(HAEntity *)entity;
// Same, showing a card-specific name instead of the entity's friendly name
- (void)configureWithEntity:(HAEntity *)entity displayName:(NSString *)displayName;

// The app's standard tap feedback: a brief 6px golden border flash
+ (void)flashTapFeedbackOnLayer:(CALayer *)layer;

@end
