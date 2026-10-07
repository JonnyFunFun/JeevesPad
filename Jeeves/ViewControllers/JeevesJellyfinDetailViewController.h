#import <UIKit/UIKit.h>
#import "JeevesRefreshable.h"

@class JeevesJellyfinItem;

@interface JeevesJellyfinDetailViewController : UIViewController <JeevesRefreshable>

- (instancetype)initWithItem:(JeevesJellyfinItem *)item;

@end
