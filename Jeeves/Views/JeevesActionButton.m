#import "JeevesActionButton.h"
#import "JeevesThemeManager.h"

static const CGFloat kIconButtonSize = 50.0;
static const CGFloat kIconImageSize = 28.0;
static const CGFloat kCornerRadius = 12.0;

@interface JeevesActionButton ()

@property (nonatomic, assign) JeevesIconType iconType;

@end

@implementation JeevesActionButton

+ (instancetype)iconButtonWithType:(JeevesIconType)iconType {
    JeevesActionButton *button = [JeevesActionButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;

    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    button.backgroundColor = [theme secondaryBackgroundColor];
    button.layer.cornerRadius = kCornerRadius;
    [button setIconType:iconType];

    // Set intrinsic content size via constraints
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:kIconButtonSize],
        [button.heightAnchor constraintEqualToConstant:kIconButtonSize]
    ]];

    return button;
}

- (void)setIconType:(JeevesIconType)iconType {
    _iconType = iconType;
    UIColor *iconColor = [[JeevesThemeManager sharedManager] textColor];
    UIImage *icon = [JeevesIconView imageWithIconType:iconType size:CGSizeMake(kIconImageSize, kIconImageSize) color:iconColor];
    [self setImage:icon forState:UIControlStateNormal];
}

@end
