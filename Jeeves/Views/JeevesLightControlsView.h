#import <UIKit/UIKit.h>

@class HAEntity;

typedef NS_ENUM(NSInteger, JeevesLightControlsStyle) {
    // One-line rows for dashboard cards: brightness, color swatches, color
    // temperature. Only as many rows as `maximumRows` allows are shown. (Cards
    // show the effect picker separately, as a JeevesLightEffectButton.)
    JeevesLightControlsStyleCompact,
    // Labelled controls for the more-info screen, including hue/saturation sliders.
    JeevesLightControlsStyleFull
};

// Opens a light's effect list and applies the chosen effect. Cards show one on their
// bottom row whenever the light has effects; the full controls include one too.
@interface JeevesLightEffectButton : UIButton

+ (instancetype)effectButtonWithStyle:(JeevesLightControlsStyle)style;

// Updates the title from the light's current effect (unless just changed by the user)
- (void)configureWithEntity:(HAEntity *)entity;

@end

// Brightness, color, color temperature and effect controls for a light, showing
// only what the entity supports. Changes are sent to Home Assistant directly.
@interface JeevesLightControlsView : UIView

- (instancetype)initWithStyle:(JeevesLightControlsStyle)style;

@property (nonatomic, assign, readonly) JeevesLightControlsStyle style;
// Room cards adjust brightness by dragging the whole card, so they hide the slider
@property (nonatomic, assign) BOOL showsBrightness;  // default YES
// Compact style only; 0 shows every supported row
@property (nonatomic, assign) NSInteger maximumRows;

// Rebuilds rows if the light's capabilities (or maximumRows) changed, otherwise
// just updates values. Values are left alone while the user is adjusting them.
- (void)configureWithEntity:(HAEntity *)entity;

// Compact layout helpers for hosts sizing the view
+ (NSInteger)compactRowCountForEntity:(HAEntity *)entity showsBrightness:(BOOL)showsBrightness;
+ (NSInteger)compactRowsFittingHeight:(CGFloat)height;
+ (CGFloat)compactHeightForRows:(NSInteger)rows;

// YES if the touch is on light controls or an effect button; hosts use this to keep their
// tap/long-press/pan recognizers from stealing touches meant for the controls.
+ (BOOL)touchIsInsideLightControls:(UITouch *)touch;

// YES while the user is dragging any light control slider; hosts skip
// refreshes that could rebuild the view under the user's finger.
+ (BOOL)isUserAdjusting;

@end
