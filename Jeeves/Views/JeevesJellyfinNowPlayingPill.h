#import <UIKit/UIKit.h>

@class JeevesJellyfinSession;
@class JeevesJellyfinNowPlayingPill;

@protocol JeevesJellyfinNowPlayingPillDelegate <NSObject>
- (void)jellyfinNowPlayingPillDidTap:(JeevesJellyfinNowPlayingPill *)pill;
@end

@interface JeevesJellyfinNowPlayingPill : UIControl

@property (nonatomic, weak)   id<JeevesJellyfinNowPlayingPillDelegate> delegate;
@property (nonatomic, strong) JeevesJellyfinSession *session;

- (void)configureWithSession:(JeevesJellyfinSession *)session;

@end
