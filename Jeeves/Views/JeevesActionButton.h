#import <UIKit/UIKit.h>
#import "JeevesIconView.h"

// Square icon button used for dashboard actions (e.g. the Edit pencil)
@interface JeevesActionButton : UIButton

+ (instancetype)iconButtonWithType:(JeevesIconType)iconType;

// Update the icon
- (void)setIconType:(JeevesIconType)iconType;

@end
