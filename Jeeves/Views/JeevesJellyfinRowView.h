#import <UIKit/UIKit.h>

@class JeevesJellyfinItem;
@class JeevesJellyfinRowView;

@protocol JeevesJellyfinRowViewDelegate <NSObject>
- (void)jellyfinRowView:(JeevesJellyfinRowView *)row didTapItem:(JeevesJellyfinItem *)item;
@optional
- (void)jellyfinRowViewDidTapHeader:(JeevesJellyfinRowView *)row;
@end

@interface JeevesJellyfinRowView : UIView

@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *sectionID; // for library-section rows
@property (nonatomic, copy)   NSString *collectionType; // Jellyfin library CollectionType
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, weak)   id<JeevesJellyfinRowViewDelegate> delegate;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setItems:(NSArray *)items;

@end
