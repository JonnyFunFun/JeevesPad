#import "JeevesLightControlsView.h"
#import "HAEntity.h"
#import "HAAPIClient.h"
#import "JeevesThemeManager.h"

static NSString * const kRowBrightness  = @"brightness";
static NSString * const kRowColor       = @"color";
static NSString * const kRowTemperature = @"temperature";
static NSString * const kRowEffect      = @"effect";

static const CGFloat kCompactRowHeight  = 30.0;
static const CGFloat kCompactRowSpacing = 6.0;
// After the user changes something, ignore server state briefly so controls
// don't snap back before Home Assistant reports the new values.
static const NSTimeInterval kLockInterval = 2.5;

// Preset swatches as Home Assistant hs_color pairs (hue 0-360, saturation 0-100)
static NSArray<NSArray<NSNumber *> *> *SwatchHSColors(void) {
    return @[@[@0, @100], @[@30, @100], @[@55, @100], @[@120, @100],
             @[@185, @100], @[@230, @100], @[@275, @100], @[@320, @80]];
}

static UIColor *ColorFromHS(CGFloat hue, CGFloat saturation) {
    return [UIColor colorWithHue:hue / 360.0 saturation:saturation / 100.0 brightness:1.0 alpha:1.0];
}

// Horizontal gradient used as a slider track (both halves), so the track itself
// shows what the slider controls.
static UIImage *GradientTrackImage(NSArray<UIColor *> *colors) {
    CGSize size = CGSizeMake(120, 6);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:3] addClip];
    NSMutableArray *cgColors = [NSMutableArray array];
    for (UIColor *c in colors) [cgColors addObject:(__bridge id)c.CGColor];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cgColors, NULL);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), gradient, CGPointZero, CGPointMake(size.width, 0), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 3, 0, 3) resizingMode:UIImageResizingModeStretch];
}

static void ApplyTrackImage(UISlider *slider, UIImage *image) {
    [slider setMinimumTrackImage:image forState:UIControlStateNormal];
    [slider setMaximumTrackImage:image forState:UIControlStateNormal];
}

// A row of color swatches, evenly spaced, showing as many as fit the width.
// Frame-based rather than a UIStackView: on iOS 9, stack views with a non-default
// alignment or an equal-spacing distribution crash when deallocated.
@interface JeevesSwatchRowView : UIView
@property (nonatomic, strong) NSArray<UIButton *> *swatches;
@property (nonatomic, assign) CGFloat swatchSize;
@end

@implementation JeevesSwatchRowView

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.swatchSize);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size = self.swatchSize;
    CGFloat minGap = 6;
    CGFloat width = self.bounds.size.width;
    NSInteger fit = MIN((NSInteger)self.swatches.count, MAX(1, (NSInteger)floor((width + minGap) / (size + minGap))));
    CGFloat gap = fit > 1 ? (width - fit * size) / (fit - 1) : 0;
    CGFloat y = floor((self.bounds.size.height - size) / 2);
    for (UIButton *swatch in self.swatches) {
        swatch.hidden = (swatch.tag >= fit);
        swatch.frame = CGRectMake(floor(swatch.tag * (size + gap)), y, size, size);
    }
}

@end

#pragma mark - Effect button

@interface JeevesLightEffectButton ()
@property (nonatomic, assign) JeevesLightControlsStyle style;
@property (nonatomic, strong) HAEntity *entity;
@property (nonatomic, strong) NSDate *lockedUntil;
@end

@implementation JeevesLightEffectButton

+ (instancetype)effectButtonWithStyle:(JeevesLightControlsStyle)style {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    JeevesLightEffectButton *button = [self buttonWithType:UIButtonTypeCustom];
    button.style = style;
    BOOL full = (style == JeevesLightControlsStyleFull);
    button.titleLabel.font = full ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:14];
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [button setTitleColor:[theme textColor] forState:UIControlStateNormal];
    button.backgroundColor = [theme secondaryBackgroundColor];
    button.layer.cornerRadius = 6;
    button.contentHorizontalAlignment = full ? UIControlContentHorizontalAlignmentLeft : UIControlContentHorizontalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    [button addTarget:button action:@selector(effectTapped) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (NSString *)titleForEffect:(NSString *)effect {
    if (self.style == JeevesLightControlsStyleFull) return effect ?: @"None";
    return [NSString stringWithFormat:@"\u2728 %@", effect ?: @"Effect"];
}

- (void)configureWithEntity:(HAEntity *)entity {
    self.entity = entity;
    // Keep the user's choice showing until Home Assistant has had time to report it
    if (self.lockedUntil && [self.lockedUntil timeIntervalSinceNow] > 0) return;
    [self setTitle:[self titleForEffect:[entity currentEffect]] forState:UIControlStateNormal];
}

- (UIViewController *)hostViewController {
    for (UIResponder *r = self.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
    }
    return nil;
}

- (void)effectTapped {
    UIViewController *host = [self hostViewController];
    NSArray<NSString *> *effects = [self.entity effectList];
    if (!host || effects.count == 0) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Effect"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *current = [self.entity currentEffect];
    NSString *entityId = self.entity.entityId;
    for (NSString *effect in effects) {
        NSString *title = [effect isEqualToString:current] ? [NSString stringWithFormat:@"\u2713 %@", effect] : effect;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.lockedUntil = [NSDate dateWithTimeIntervalSinceNow:kLockInterval];
            [self setTitle:[self titleForEffect:effect] forState:UIControlStateNormal];
            [[HAAPIClient sharedClient] callService:@"light" service:@"turn_on" entityId:entityId
                                         parameters:@{@"effect": effect}
                                         completion:^(BOOL success, id result, NSError *error) {
                if (!success) NSLog(@"[LightControls] Setting effect %@ on %@ failed: %@", effect, entityId, error);
            }];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self;
    sheet.popoverPresentationController.sourceRect = self.bounds;
    [host presentViewController:sheet animated:YES completion:nil];
}

@end

// Number of sliders currently being dragged, across all instances
static NSInteger gActiveSliderTouches = 0;

@interface JeevesLightControlsView ()
@property (nonatomic, assign, readwrite) JeevesLightControlsStyle style;
@property (nonatomic, strong) HAEntity *entity;
@property (nonatomic, copy) NSString *layoutSignature;
@property (nonatomic, strong) NSDate *lockedUntil;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, assign) NSInteger activeSliderTouches;

@property (nonatomic, strong) UISlider *brightnessSlider;
@property (nonatomic, strong) UILabel *brightnessLabel;
@property (nonatomic, strong) JeevesSwatchRowView *swatchRow;
@property (nonatomic, strong) UIView *colorPreview;
@property (nonatomic, strong) UISlider *hueSlider;
@property (nonatomic, strong) UISlider *saturationSlider;
@property (nonatomic, strong) UISlider *temperatureSlider;
@property (nonatomic, strong) UILabel *temperatureLabel;
@property (nonatomic, strong) JeevesLightEffectButton *effectButton;
@end

@implementation JeevesLightControlsView

- (instancetype)initWithStyle:(JeevesLightControlsStyle)style {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _style = style;
        _showsBrightness = YES;

        _stack = [[UIStackView alloc] init];
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = (style == JeevesLightControlsStyleCompact) ? kCompactRowSpacing : 10;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor      constraintEqualToAnchor:self.topAnchor],
            [_stack.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            // Full style sizes itself from its rows; compact hosts size it explicitly
            (style == JeevesLightControlsStyleFull)
                ? [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
                : [_stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

#pragma mark - Layout helpers

+ (NSArray<NSString *> *)rowKindsForEntity:(HAEntity *)entity showsBrightness:(BOOL)showsBrightness includeEffect:(BOOL)includeEffect {
    if (entity.entityType != HAEntityTypeLight) return @[];
    NSMutableArray *kinds = [NSMutableArray array];
    if (showsBrightness && [entity supportsBrightness]) [kinds addObject:kRowBrightness];
    if ([entity supportsColor])                         [kinds addObject:kRowColor];
    if ([entity supportsColorTemperature])              [kinds addObject:kRowTemperature];
    if (includeEffect && [entity effectList].count > 0) [kinds addObject:kRowEffect];
    return kinds;
}

+ (NSInteger)compactRowCountForEntity:(HAEntity *)entity showsBrightness:(BOOL)showsBrightness {
    return [self rowKindsForEntity:entity showsBrightness:showsBrightness includeEffect:NO].count;
}

+ (NSInteger)compactRowsFittingHeight:(CGFloat)height {
    if (height < kCompactRowHeight) return 0;
    return (NSInteger)floor((height + kCompactRowSpacing) / (kCompactRowHeight + kCompactRowSpacing));
}

+ (CGFloat)compactHeightForRows:(NSInteger)rows {
    return rows > 0 ? rows * kCompactRowHeight + (rows - 1) * kCompactRowSpacing : 0;
}

+ (BOOL)touchIsInsideLightControls:(UITouch *)touch {
    for (UIView *v = touch.view; v; v = v.superview) {
        if ([v isKindOfClass:self] || [v isKindOfClass:[JeevesLightEffectButton class]]) return YES;
    }
    return NO;
}

#pragma mark - Configuration

- (void)configureWithEntity:(HAEntity *)entity {
    self.entity = entity;

    NSArray<NSString *> *kinds = [[self class] rowKindsForEntity:entity
                                                 showsBrightness:self.showsBrightness
                                                   includeEffect:(self.style == JeevesLightControlsStyleFull)];
    if (self.style == JeevesLightControlsStyleCompact && self.maximumRows > 0 && kinds.count > (NSUInteger)self.maximumRows) {
        kinds = [kinds subarrayWithRange:NSMakeRange(0, self.maximumRows)];
    }
    NSString *signature = [kinds componentsJoinedByString:@","];
    if (![signature isEqualToString:self.layoutSignature]) {
        self.layoutSignature = signature;
        [self buildRows:kinds];
        self.lockedUntil = nil;
    }
    [self updateValues];
}

- (void)buildRows:(NSArray<NSString *> *)kinds {
    for (UIView *v in [self.stack.arrangedSubviews copy]) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.brightnessSlider = nil; self.brightnessLabel = nil;
    self.swatchRow = nil; self.colorPreview = nil; self.hueSlider = nil; self.saturationSlider = nil;
    self.temperatureSlider = nil; self.temperatureLabel = nil;
    self.effectButton = nil;

    BOOL full = (self.style == JeevesLightControlsStyleFull);
    for (NSString *kind in kinds) {
        if ([kind isEqualToString:kRowBrightness]) {
            self.brightnessSlider = [self sliderWithMin:1 max:100 action:@selector(brightnessCommitted)];
            self.brightnessSlider.minimumTrackTintColor = [[JeevesThemeManager sharedManager] onColor];
            if (full) {
                self.brightnessLabel = [self captionLabel];
                [self.brightnessSlider addTarget:self action:@selector(updateCaptions) forControlEvents:UIControlEventValueChanged];
                [self addRow:self.brightnessLabel];
            }
            [self addRow:self.brightnessSlider];
        } else if ([kind isEqualToString:kRowColor]) {
            if (full) {
                UILabel *caption = [self captionLabel];
                caption.text = @"Color";
                self.colorPreview = [[UIView alloc] init];
                self.colorPreview.layer.cornerRadius = 12;
                self.colorPreview.layer.borderWidth = 1;
                self.colorPreview.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
                [self.colorPreview.widthAnchor constraintEqualToConstant:48].active = YES;
                [self.colorPreview.heightAnchor constraintEqualToConstant:24].active = YES;
                // Plain constraints, not a center-aligned UIStackView (crashes on dealloc on iOS 9)
                caption.translatesAutoresizingMaskIntoConstraints = NO;
                self.colorPreview.translatesAutoresizingMaskIntoConstraints = NO;
                UIView *header = [[UIView alloc] init];
                [header addSubview:caption];
                [header addSubview:self.colorPreview];
                [NSLayoutConstraint activateConstraints:@[
                    [caption.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
                    [caption.topAnchor constraintEqualToAnchor:header.topAnchor],
                    [caption.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
                    [self.colorPreview.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
                    [self.colorPreview.centerYAnchor constraintEqualToAnchor:caption.centerYAnchor],
                ]];
                [self addRow:header];
            }
            [self addRow:[self makeSwatchRow]];
            if (full) {
                NSMutableArray *rainbow = [NSMutableArray array];
                for (NSInteger h = 0; h <= 360; h += 60) [rainbow addObject:ColorFromHS(h, 100)];
                self.hueSlider = [self sliderWithMin:0 max:360 action:@selector(colorSlidersCommitted)];
                ApplyTrackImage(self.hueSlider, GradientTrackImage(rainbow));
                self.saturationSlider = [self sliderWithMin:0 max:100 action:@selector(colorSlidersCommitted)];
                [self.hueSlider addTarget:self action:@selector(colorSlidersChanged) forControlEvents:UIControlEventValueChanged];
                [self.saturationSlider addTarget:self action:@selector(colorSlidersChanged) forControlEvents:UIControlEventValueChanged];
                [self addRow:self.hueSlider];
                [self addRow:self.saturationSlider];
            }
        } else if ([kind isEqualToString:kRowTemperature]) {
            self.temperatureSlider = [self sliderWithMin:[self.entity minColorTemperatureKelvin]
                                                     max:[self.entity maxColorTemperatureKelvin]
                                                  action:@selector(temperatureCommitted)];
            ApplyTrackImage(self.temperatureSlider, GradientTrackImage(@[
                [UIColor colorWithRed:1.00 green:0.62 blue:0.25 alpha:1.0],
                [UIColor colorWithRed:1.00 green:0.87 blue:0.72 alpha:1.0],
                [UIColor colorWithRed:0.84 green:0.90 blue:1.00 alpha:1.0],
            ]));
            if (full) {
                self.temperatureLabel = [self captionLabel];
                [self.temperatureSlider addTarget:self action:@selector(updateCaptions) forControlEvents:UIControlEventValueChanged];
                [self addRow:self.temperatureLabel];
            }
            [self addRow:self.temperatureSlider];
        } else if ([kind isEqualToString:kRowEffect]) {
            self.effectButton = [JeevesLightEffectButton effectButtonWithStyle:self.style];
            [self.effectButton.heightAnchor constraintEqualToConstant:44].active = YES;
            [self addRow:self.effectButton];
        }
    }
}

- (void)addRow:(UIView *)row {
    if (self.style == JeevesLightControlsStyleCompact) {
        [row.heightAnchor constraintEqualToConstant:kCompactRowHeight].active = YES;
    }
    [self.stack addArrangedSubview:row];
}

- (UILabel *)captionLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:17];
    label.textColor = [[JeevesThemeManager sharedManager] textColor];
    return label;
}

- (UISlider *)sliderWithMin:(float)min max:(float)max action:(SEL)commitAction {
    UISlider *slider = [[UISlider alloc] init];
    slider.minimumValue = min;
    slider.maximumValue = MAX(max, min + 1);
    // Send to Home Assistant once, when the finger lifts
    [slider addTarget:self action:commitAction forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [slider addTarget:self action:@selector(sliderTouchBegan) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(sliderTouchEnded)
     forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return slider;
}

- (void)sliderTouchBegan {
    self.activeSliderTouches++;
    gActiveSliderTouches++;
}

- (void)sliderTouchEnded {
    if (self.activeSliderTouches == 0) return;
    self.activeSliderTouches--;
    gActiveSliderTouches--;
}

- (void)dealloc {
    // A slider removed mid-drag never reports touch-up; don't leave refreshes paused
    gActiveSliderTouches -= _activeSliderTouches;
}

+ (BOOL)isUserAdjusting {
    return gActiveSliderTouches > 0;
}

- (UIView *)makeSwatchRow {
    BOOL full = (self.style == JeevesLightControlsStyleFull);
    CGFloat size = full ? 32 : 24;
    JeevesSwatchRowView *row = [[JeevesSwatchRowView alloc] init];
    row.swatchSize = size;
    NSMutableArray *buttons = [NSMutableArray array];
    NSArray *colors = SwatchHSColors();
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *swatch = [UIButton buttonWithType:UIButtonTypeCustom];
        swatch.tag = i;
        swatch.backgroundColor = ColorFromHS([colors[i][0] doubleValue], [colors[i][1] doubleValue]);
        swatch.layer.cornerRadius = size / 2;
        swatch.layer.borderColor = [UIColor whiteColor].CGColor;
        [swatch addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:swatch];
        [buttons addObject:swatch];
    }
    row.swatches = buttons;
    self.swatchRow = row;
    return row;
}

#pragma mark - Values

- (BOOL)isLocked {
    return self.lockedUntil && [self.lockedUntil timeIntervalSinceNow] > 0;
}

- (void)lock {
    self.lockedUntil = [NSDate dateWithTimeIntervalSinceNow:kLockInterval];
}

- (void)updateValues {
    HAEntity *e = self.entity;
    if ([self isLocked]) return;

    if (self.brightnessSlider && !self.brightnessSlider.tracking) {
        self.brightnessSlider.value = [e isOn] ? MAX(1, [e brightness]) : 1;
    }
    if (self.temperatureSlider && !self.temperatureSlider.tracking) {
        NSInteger k = [e colorTemperatureKelvin];
        self.temperatureSlider.value = k > 0 ? k : (self.temperatureSlider.minimumValue + self.temperatureSlider.maximumValue) / 2;
    }
    if (self.hueSlider && !self.hueSlider.tracking && !self.saturationSlider.tracking && [e hasHSColor]) {
        self.hueSlider.value = [e hue];
        self.saturationSlider.value = [e saturation];
    }
    [self.effectButton configureWithEntity:e];
    [self updateColorIndicators];
    [self updateCaptions];
}

// Ring the swatch matching the light's current color, and refresh the preview/tracks
- (void)updateColorIndicators {
    HAEntity *e = self.entity;
    BOOL inColorMode = [e isOn] && [e hasHSColor] && ![e.attributes[@"color_mode"] isEqual:@"color_temp"];
    CGFloat hue = self.hueSlider ? self.hueSlider.value : [e hue];
    CGFloat sat = self.saturationSlider ? self.saturationSlider.value : [e saturation];

    NSArray *colors = SwatchHSColors();
    for (UIButton *swatch in self.swatchRow.swatches) {
        CGFloat swatchHue = [colors[swatch.tag][0] doubleValue];
        CGFloat diff = fabs(fmod(hue - swatchHue + 540.0, 360.0) - 180.0);
        swatch.layer.borderWidth = (inColorMode && sat > 40 && diff < 12) ? 2.5 : 0;
    }
    if (self.saturationSlider) {
        ApplyTrackImage(self.saturationSlider, GradientTrackImage(@[[UIColor whiteColor], ColorFromHS(self.hueSlider.value, 100)]));
    }
    self.colorPreview.backgroundColor = inColorMode || self.hueSlider.tracking || self.saturationSlider.tracking
        ? ColorFromHS(hue, sat)
        : [UIColor clearColor];
}

- (void)updateCaptions {
    if (self.brightnessLabel) {
        self.brightnessLabel.text = [NSString stringWithFormat:@"Brightness %ld%%", (long)lroundf(self.brightnessSlider.value)];
    }
    if (self.temperatureLabel) {
        self.temperatureLabel.text = [NSString stringWithFormat:@"Color temperature %ld K", (long)lroundf(self.temperatureSlider.value)];
    }
}

#pragma mark - Actions

- (void)turnOnWithParameters:(NSDictionary *)parameters {
    [self lock];
    NSString *entityId = self.entity.entityId;
    [[HAAPIClient sharedClient] callService:@"light" service:@"turn_on" entityId:entityId parameters:parameters completion:^(BOOL success, id result, NSError *error) {
        if (!success) NSLog(@"[LightControls] light.turn_on %@ failed for %@: %@", parameters, entityId, error);
    }];
}

- (void)brightnessCommitted {
    // Convert 1-100% to HA's 0-255 scale, rounding up so 1% stays on
    NSInteger percent = lroundf(self.brightnessSlider.value);
    [self turnOnWithParameters:@{@"brightness": @(MAX(3, (percent * 255 + 99) / 100))}];
}

- (void)swatchTapped:(UIButton *)swatch {
    NSArray *hs = SwatchHSColors()[swatch.tag];
    self.hueSlider.value = [hs[0] floatValue];
    self.saturationSlider.value = [hs[1] floatValue];
    [self turnOnWithParameters:@{@"hs_color": hs}];
    // Reflect the choice immediately, before HA reports back
    NSMutableDictionary *attrs = [self.entity.attributes mutableCopy] ?: [NSMutableDictionary dictionary];
    attrs[@"hs_color"] = hs;
    attrs[@"color_mode"] = @"hs";
    self.entity.attributes = attrs;
    self.entity.state = @"on";
    [self updateColorIndicators];
}

- (void)colorSlidersChanged {
    [self updateColorIndicators];
}

- (void)colorSlidersCommitted {
    [self turnOnWithParameters:@{@"hs_color": @[@(lroundf(self.hueSlider.value)), @(lroundf(self.saturationSlider.value))]}];
}

- (void)temperatureCommitted {
    NSInteger kelvin = lroundf(self.temperatureSlider.value);
    if ([self.entity usesKelvinColorTemperature]) {
        [self turnOnWithParameters:@{@"color_temp_kelvin": @(kelvin)}];
    } else {
        // Older Home Assistant versions only accept mireds
        [self turnOnWithParameters:@{@"color_temp": @(lround(1000000.0 / kelvin))}];
    }
}

@end
