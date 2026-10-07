#import "UIViewController+JeevesRefresh.h"
#import <objc/runtime.h>

static const void *kJeevesRefreshControlKey   = &kJeevesRefreshControlKey;
static const void *kJeevesRefreshTimerKey     = &kJeevesRefreshTimerKey;
static const void *kJeevesWakeObserverFlagKey = &kJeevesWakeObserverFlagKey;
static const void *kJeevesBgObserverFlagKey   = &kJeevesBgObserverFlagKey;

@implementation UIViewController (JeevesRefresh)

#pragma mark - Pull to refresh

- (UIRefreshControl *)jeeves_installPullToRefreshOnScrollView:(UIScrollView *)scrollView {
    if (!scrollView) return nil;
    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    rc.tintColor = [UIColor whiteColor];
    [rc addTarget:self action:@selector(jeeves_pullRefreshTriggered:) forControlEvents:UIControlEventValueChanged];
    if ([scrollView isKindOfClass:[UITableView class]] || [scrollView isKindOfClass:[UICollectionView class]]) {
        // iOS 10+ has refreshControl property; for iOS 9 just addSubview.
        [scrollView addSubview:rc];
    } else {
        scrollView.alwaysBounceVertical = YES;
        [scrollView addSubview:rc];
    }
    objc_setAssociatedObject(self, kJeevesRefreshControlKey, rc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return rc;
}

- (void)jeeves_pullRefreshTriggered:(UIRefreshControl *)sender {
    if ([self conformsToProtocol:@protocol(JeevesRefreshable)]) {
        [(id<JeevesRefreshable>)self refreshFromSource:JeevesRefreshSourcePullToRefresh];
    } else {
        [sender endRefreshing];
    }
}

- (void)jeeves_endRefreshing {
    UIRefreshControl *rc = objc_getAssociatedObject(self, kJeevesRefreshControlKey);
    if (rc.isRefreshing) {
        [rc endRefreshing];
    }
}

#pragma mark - Wake observer

- (void)jeeves_installWakeRefreshObserver {
    NSNumber *installed = objc_getAssociatedObject(self, kJeevesWakeObserverFlagKey);
    if (installed.boolValue) return;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jeeves_didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jeeves_didEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    objc_setAssociatedObject(self, kJeevesWakeObserverFlagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)jeeves_removeWakeRefreshObserver {
    NSNumber *installed = objc_getAssociatedObject(self, kJeevesWakeObserverFlagKey);
    if (!installed.boolValue) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidEnterBackgroundNotification
                                                  object:nil];
    objc_setAssociatedObject(self, kJeevesWakeObserverFlagKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)jeeves_didBecomeActive:(NSNotification *)note {
    if (![self isViewLoaded] || self.view.window == nil) return;
    if ([self conformsToProtocol:@protocol(JeevesRefreshable)]) {
        [(id<JeevesRefreshable>)self refreshFromSource:JeevesRefreshSourceWakeFromSleep];
    }
    // Re-arm timer if it was running pre-background
    NSNumber *wasBg = objc_getAssociatedObject(self, kJeevesBgObserverFlagKey);
    if (wasBg.boolValue) {
        objc_setAssociatedObject(self, kJeevesBgObserverFlagKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self jeeves_startRefreshTimer];
    }
}

- (void)jeeves_didEnterBackground:(NSNotification *)note {
    NSTimer *t = objc_getAssociatedObject(self, kJeevesRefreshTimerKey);
    if (t) {
        [t invalidate];
        objc_setAssociatedObject(self, kJeevesRefreshTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kJeevesBgObserverFlagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - Timer

- (void)jeeves_startRefreshTimer {
    NSTimer *existing = objc_getAssociatedObject(self, kJeevesRefreshTimerKey);
    if (existing) return;

    NSTimeInterval interval = 5.0;
    if ([self conformsToProtocol:@protocol(JeevesRefreshable)]
        && [self respondsToSelector:@selector(refreshPollingInterval)]) {
        interval = [(id<JeevesRefreshable>)self refreshPollingInterval];
    }
    if (interval <= 0) return;

    BOOL shouldPoll = YES;
    if ([self conformsToProtocol:@protocol(JeevesRefreshable)]
        && [self respondsToSelector:@selector(refreshShouldPollWhenVisible)]) {
        shouldPoll = [(id<JeevesRefreshable>)self refreshShouldPollWhenVisible];
    }
    if (!shouldPoll) return;

    NSTimer *timer = [NSTimer timerWithTimeInterval:interval
                                             target:self
                                           selector:@selector(jeeves_timerFired:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(self, kJeevesRefreshTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)jeeves_stopRefreshTimer {
    NSTimer *t = objc_getAssociatedObject(self, kJeevesRefreshTimerKey);
    if (t) {
        [t invalidate];
        objc_setAssociatedObject(self, kJeevesRefreshTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)jeeves_timerFired:(NSTimer *)timer {
    if ([self conformsToProtocol:@protocol(JeevesRefreshable)]) {
        [(id<JeevesRefreshable>)self refreshFromSource:JeevesRefreshSourceTimer];
    }
}

@end
