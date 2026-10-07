#import <UIKit/UIKit.h>
#import "JeevesRefreshable.h"

@interface UIViewController (JeevesRefresh)

- (UIRefreshControl *)jeeves_installPullToRefreshOnScrollView:(UIScrollView *)scrollView;
- (void)jeeves_installWakeRefreshObserver;
- (void)jeeves_removeWakeRefreshObserver;
- (void)jeeves_startRefreshTimer;
- (void)jeeves_stopRefreshTimer;
- (void)jeeves_endRefreshing;

@end
