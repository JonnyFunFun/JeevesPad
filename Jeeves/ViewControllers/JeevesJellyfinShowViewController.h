#import <UIKit/UIKit.h>
#import "JeevesRefreshable.h"

@class JeevesJellyfinItem;

typedef NS_ENUM(NSInteger, JeevesJellyfinShowMode) {
    JeevesJellyfinShowModeShow   = 0, // show -> seasons
    JeevesJellyfinShowModeSeason = 1  // season -> episodes
};

@interface JeevesJellyfinShowViewController : UIViewController <JeevesRefreshable>

- (instancetype)initWithItem:(JeevesJellyfinItem *)item mode:(JeevesJellyfinShowMode)mode;

@end
