#import <UIKit/UIKit.h>
#import "JeevesRefreshable.h"

@interface JeevesJellyfinSearchViewController : UIViewController <JeevesRefreshable>

- (instancetype)initWithQuery:(NSString *)query;

@end
