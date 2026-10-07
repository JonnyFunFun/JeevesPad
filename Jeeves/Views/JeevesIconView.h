#import <UIKit/UIKit.h>

// Icon names that correspond to SVG files
typedef NS_ENUM(NSInteger, JeevesIconType) {
    JeevesIconTypeHouse,
    JeevesIconTypeLivingRoom,
    JeevesIconTypeKitchen,
    JeevesIconTypeBathTub,
    JeevesIconTypeBed,
    JeevesIconTypeGarage,
    JeevesIconTypeWork,
    JeevesIconTypeBabyCrib,
    JeevesIconTypeGear,
    JeevesIconTypePlus,
    JeevesIconTypePencil,
    // Weather icons
    JeevesIconTypeSun,
    JeevesIconTypeCloud,
    JeevesIconTypeRain,
    JeevesIconTypeSnow,
    JeevesIconTypeStorm,
    JeevesIconTypePartlyCloudy
};

@interface JeevesIconView : UIView

@property (nonatomic, assign) JeevesIconType iconType;
@property (nonatomic, strong) UIColor *iconColor;
@property (nonatomic, assign) CGFloat iconInset; // Padding inside the view

- (instancetype)initWithIconType:(JeevesIconType)iconType;
- (instancetype)initWithIconType:(JeevesIconType)iconType color:(UIColor *)color;

// Convenience method to get an image from the icon (for buttons)
+ (UIImage *)imageWithIconType:(JeevesIconType)iconType size:(CGSize)size color:(UIColor *)color;

@end
