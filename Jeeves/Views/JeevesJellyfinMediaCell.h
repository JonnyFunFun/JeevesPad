#import <UIKit/UIKit.h>

@class JeevesJellyfinItem;

@interface JeevesJellyfinMediaCell : UICollectionViewCell

@property (nonatomic, strong, readonly) UIImageView *posterView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UIView *progressBar;
@property (nonatomic, strong) JeevesJellyfinItem *item;

- (void)configureWithItem:(JeevesJellyfinItem *)item;

@end
