#import <UIKit/UIKit.h>
#import "JeevesRefreshable.h"

@interface JeevesJellyfinLibraryViewController : UIViewController <JeevesRefreshable>

- (instancetype)initWithLibraryID:(NSString *)libraryID title:(NSString *)title collectionType:(NSString *)collectionType;

@end
