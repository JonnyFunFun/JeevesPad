#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, JeevesRefreshSource) {
    JeevesRefreshSourcePullToRefresh = 1 << 0,
    JeevesRefreshSourceWakeFromSleep = 1 << 1,
    JeevesRefreshSourceTimer         = 1 << 2,
    JeevesRefreshSourceManual        = 1 << 3
};

@protocol JeevesRefreshable <NSObject>
@required
- (void)refreshFromSource:(JeevesRefreshSource)source;
@optional
- (NSTimeInterval)refreshPollingInterval; // default 5.0
- (BOOL)refreshShouldPollWhenVisible;     // default YES
@end
