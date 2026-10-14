#import "JeevesLightToggleCell.h"
#import "HAEntity.h"
#import "JeevesThemeManager.h"
#import "JeevesLightControlsView.h"

@interface JeevesLightToggleCell () <UIGestureRecognizerDelegate>

// Store weak reference to avoid retain cycles and stale references
@property (nonatomic, weak, readwrite) HAEntity *entity;
// Cache entityId separately since we need it even if entity is deallocated
// Redeclare as readwrite since header declares it readonly
@property (nonatomic, copy, readwrite) NSString *entityId;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) NSLayoutConstraint *fillHeightConstraint;
@property (nonatomic, assign) BOOL isDimmable;
@property (nonatomic, assign) BOOL isReadOnly; // For sensors - no toggle/dim
@property (nonatomic, assign) BOOL isScript;   // For scripts - tap to trigger
@property (nonatomic, strong) CAShapeLayer *playIconLayer; // Drawn play triangle for scripts
@property (nonatomic, assign) BOOL cachedIsOn;
@property (nonatomic, assign) NSInteger cachedBrightness;
@property (nonatomic, assign) CGFloat panStartBrightness;
@property (nonatomic, assign) CGFloat panStartY;
@property (nonatomic, assign) BOOL isPanning;
@property (nonatomic, assign) NSTimeInterval lastBrightnessUpdateTime;
@property (nonatomic, assign) NSInteger lastSentBrightness;
// Inline color/temperature/effect controls for lights, shown when the card has room
@property (nonatomic, strong) UIView *controlsArea;
@property (nonatomic, strong) JeevesLightControlsView *controlsView;
@property (nonatomic, strong) NSLayoutConstraint *controlsHeightConstraint;
// Effect picker, always shown (bottom-right, level with the status) when the light has effects
@property (nonatomic, strong) JeevesLightEffectButton *effectButton;
@property (nonatomic, strong) UIPanGestureRecognizer *brightnessPan;

@end

@implementation JeevesLightToggleCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    _allowsBrightnessDrag = YES;
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];

    self.contentView.backgroundColor = [theme cardBackgroundColor];
    self.contentView.layer.cornerRadius = 16;
    self.contentView.layer.masksToBounds = YES;

    // Fill view for brightness level (bottom-up fill)
    self.fillView = [[UIView alloc] init];
    self.fillView.backgroundColor = [[theme onColor] colorWithAlphaComponent:0.3];
    self.fillView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.fillView];

    // Name label - large, prominent, left-aligned at top
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:22];
    self.nameLabel.textColor = [theme textColor];
    self.nameLabel.textAlignment = NSTextAlignmentLeft;
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.6;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    // Status label - ON/OFF or percentage, left-aligned
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:32];
    self.statusLabel.textAlignment = NSTextAlignmentLeft;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.statusLabel];

    // Space between the name and status for inline light controls
    self.controlsArea = [[UIView alloc] init];
    self.controlsArea.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.controlsArea];

    // Brightness is set by dragging the card, so the controls omit that row
    self.controlsView = [[JeevesLightControlsView alloc] initWithStyle:JeevesLightControlsStyleCompact];
    self.controlsView.showsBrightness = NO;
    self.controlsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlsView.hidden = YES;
    [self.controlsArea addSubview:self.controlsView];
    self.controlsHeightConstraint = [self.controlsView.heightAnchor constraintEqualToConstant:0];

    self.effectButton = [JeevesLightEffectButton effectButtonWithStyle:JeevesLightControlsStyleCompact];
    self.effectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.effectButton.hidden = YES;
    // On narrow cards the effect name truncates before the status does
    [self.effectButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:self.effectButton];

    // Fill view constraints - anchored to bottom, height varies
    self.fillHeightConstraint = [self.fillView.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        // Fill view at bottom
        [self.fillView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.fillView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.fillView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        self.fillHeightConstraint,

        // Name at top, left-aligned
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],

        // Status below name, left-aligned
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.effectButton.leadingAnchor constant:-8],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],

        // Effect button bottom-right, level with the status
        [self.effectButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.effectButton.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.effectButton.heightAnchor constraintEqualToConstant:30],
        [self.effectButton.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.6],

        // Controls area fills the gap between name and status
        [self.controlsArea.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:6],
        [self.controlsArea.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor constant:-6],
        [self.controlsArea.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.controlsArea.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.controlsView.topAnchor constraintEqualToAnchor:self.controlsArea.topAnchor],
        [self.controlsView.leadingAnchor constraintEqualToAnchor:self.controlsArea.leadingAnchor],
        [self.controlsView.trailingAnchor constraintEqualToAnchor:self.controlsArea.trailingAnchor],
        self.controlsHeightConstraint,
    ]];

    // Pan gesture for brightness (vertical slide)
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [self.contentView addGestureRecognizer:pan];
    self.brightnessPan = pan;

    // Tap gesture for toggle
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleTapped)];
    tap.delegate = self;
    [self.contentView addGestureRecognizer:tap];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.brightnessPan) {
        // Only claim the drag when it sets brightness; otherwise let the dashboard scroll
        return self.allowsBrightnessDrag && self.isDimmable && !self.isReadOnly && self.entityId != nil;
    }
    return YES;
}

- (void)setAllowsBrightnessDrag:(BOOL)allowsBrightnessDrag {
    if (_allowsBrightnessDrag == allowsBrightnessDrag) return;
    _allowsBrightnessDrag = allowsBrightnessDrag;
    // Without the drag, offer the brightness slider among the inline controls
    self.controlsView.showsBrightness = !allowsBrightnessDrag;
    [self updateLightControls];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // Toggle/brightness-drag must not steal touches from the inline light controls
    return ![JeevesLightControlsView touchIsInsideLightControls:touch];
}

// Shows as many control rows as fit between the name and status labels, plus the
// effect button whenever the light has effects
- (void)updateLightControls {
    HAEntity *entity = self.entity;
    BOOL hasEffects = [entity effectList].count > 0;
    if (self.effectButton.hidden == hasEffects) self.effectButton.hidden = !hasEffects;
    if (hasEffects) [self.effectButton configureWithEntity:entity];

    NSInteger supported = entity ? [JeevesLightControlsView compactRowCountForEntity:entity showsBrightness:self.controlsView.showsBrightness] : 0;
    NSInteger rows = MIN(supported, [JeevesLightControlsView compactRowsFittingHeight:self.controlsArea.bounds.size.height]);
    if (self.controlsArea.bounds.size.width < 120) rows = 0;

    self.controlsView.hidden = (rows == 0);
    if (rows == 0) return;
    self.controlsView.maximumRows = rows;
    CGFloat height = [JeevesLightControlsView compactHeightForRows:rows];
    if (self.controlsHeightConstraint.constant != height) {
        self.controlsHeightConstraint.constant = height;
    }
    [self.controlsView configureWithEntity:entity];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Clear all references when cell is about to be reused
    self.controlsView.hidden = YES;
    self.effectButton.hidden = YES;
    self.entity = nil;
    self.entityId = nil;
    self.isDimmable = NO;
    self.isReadOnly = NO;
    self.isScript = NO;
    self.cachedIsOn = NO;
    self.cachedBrightness = 0;
    self.isPanning = NO;
    // Remove play icon if present
    [self.playIconLayer removeFromSuperlayer];
    self.playIconLayer = nil;
    // Clear any border animations and state
    [self.contentView.layer removeAnimationForKey:@"flashBorder"];
    [self.contentView.layer removeAnimationForKey:@"borderColor"];
    self.contentView.layer.borderWidth = 0;
    self.contentView.layer.borderColor = [UIColor clearColor].CGColor;
}

- (void)configureWithEntity:(HAEntity *)entity {
    [self configureWithEntity:entity displayName:nil];
}

- (void)configureWithEntity:(HAEntity *)entity displayName:(NSString *)displayName {
    NSLog(@"[JeevesLightToggleCell] configureWithEntity called, entity: %@", entity.entityId);
    if (!entity) {
        NSLog(@"[JeevesLightToggleCell] entity is nil in configureWithEntity");
        return;
    }

    // Clean up any existing play icon from previous configuration
    [self.playIconLayer removeFromSuperlayer];
    self.playIconLayer = nil;

    // Store weak reference to entity and cache entityId separately
    self.entity = entity;
    self.entityId = [entity.entityId copy];
    [self updateLightControls];

    // Check if this is a read-only sensor
    BOOL isReadOnly = (entity.entityType == HAEntityTypeSensor || entity.entityType == HAEntityTypeBinarySensor);
    self.isReadOnly = isReadOnly;

    // Check if this is a script or button (tap to trigger, no on/off state)
    BOOL isScript = (entity.entityType == HAEntityTypeScript || entity.entityType == HAEntityTypeButton);
    self.isScript = isScript;

    // Get all values from entity upfront and cache them
    NSString *friendlyName = entity.friendlyName ?: @"";
    BOOL isDimmable = isReadOnly ? NO : [entity supportsBrightness];
    BOOL isOn = entity.isOn;
    NSInteger brightness = isDimmable ? [entity brightness] : 100;

    NSLog(@"[JeevesLightToggleCell] isDimmable: %d, isOn: %d, brightness: %ld, isReadOnly: %d", isDimmable, isOn, (long)brightness, isReadOnly);

    // Cache all state
    self.isDimmable = isDimmable;
    self.cachedIsOn = isOn;
    self.cachedBrightness = brightness;

    // Get theme
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    if (!theme) {
        NSLog(@"[JeevesLightToggleCell] theme is nil!");
        return;
    }

    // Update all UI elements
    self.nameLabel.text = displayName.length > 0 ? displayName : friendlyName;
    self.contentView.backgroundColor = [theme cardBackgroundColor];

    // Handle scripts - show drawn play triangle and tap to trigger
    if (isScript) {
        self.nameLabel.textColor = [theme textColor];
        self.statusLabel.text = @""; // Clear text, we'll draw the icon
        self.fillView.hidden = YES;
        [self updateFillForBrightness:0];

        // Remove existing play icon if any
        [self.playIconLayer removeFromSuperlayer];

        // Draw play triangle - positioned at bottom left like statusLabel
        CGFloat iconSize = 32.0;
        CGFloat padding = 12.0;

        UIBezierPath *trianglePath = [UIBezierPath bezierPath];
        // Draw right-pointing triangle (play icon)
        [trianglePath moveToPoint:CGPointMake(0, 0)];
        [trianglePath addLineToPoint:CGPointMake(iconSize, iconSize / 2)];
        [trianglePath addLineToPoint:CGPointMake(0, iconSize)];
        [trianglePath closePath];

        self.playIconLayer = [CAShapeLayer layer];
        self.playIconLayer.path = trianglePath.CGPath;
        self.playIconLayer.fillColor = [theme onColor].CGColor;
        self.playIconLayer.frame = CGRectMake(padding, self.contentView.bounds.size.height - iconSize - padding, iconSize, iconSize);
        [self.contentView.layer addSublayer:self.playIconLayer];
    }
    // Handle sensors differently - show state/value with unit
    else if (isReadOnly) {
        self.nameLabel.textColor = [theme textColor];
        NSString *unit = entity.attributes[@"unit_of_measurement"] ?: @"";
        NSString *state = entity.state ?: @"--";
        if (unit.length > 0) {
            self.statusLabel.text = [NSString stringWithFormat:@"%@ %@", state, unit];
        } else {
            // Binary sensor - show state nicely
            if ([state isEqualToString:@"on"]) {
                self.statusLabel.text = @"ON";
                self.statusLabel.textColor = [theme onColor];
            } else if ([state isEqualToString:@"off"]) {
                self.statusLabel.text = @"OFF";
                self.statusLabel.textColor = [theme secondaryTextColor];
            } else {
                self.statusLabel.text = [state capitalizedString];
                self.statusLabel.textColor = [theme textColor];
            }
        }
        if (entity.entityType == HAEntityTypeSensor) {
            self.statusLabel.textColor = [theme textColor];
        }
        self.fillView.hidden = YES;
        [self updateFillForBrightness:0];
    } else if (isOn) {
        NSLog(@"[JeevesLightToggleCell] entity is ON");
        self.nameLabel.textColor = [theme textColor];
        self.statusLabel.textColor = [theme onColor];
        self.fillView.backgroundColor = [[theme onColor] colorWithAlphaComponent:0.3];
        self.fillView.hidden = NO;

        if (isDimmable) {
            self.statusLabel.text = [NSString stringWithFormat:@"%ld%%", (long)brightness];
        } else {
            self.statusLabel.text = @"ON";
            brightness = 100;
        }
        [self updateFillForBrightness:brightness];
    } else {
        NSLog(@"[JeevesLightToggleCell] entity is OFF");
        self.nameLabel.textColor = [theme secondaryTextColor];
        self.statusLabel.text = @"OFF";
        self.statusLabel.textColor = [theme secondaryTextColor];
        self.fillView.hidden = YES;
        [self updateFillForBrightness:0];
    }
    NSLog(@"[JeevesLightToggleCell] configureWithEntity done");
}

- (void)updateFillForBrightness:(NSInteger)brightness {
    if (!self.fillHeightConstraint) {
        NSLog(@"[JeevesLightToggleCell] fillHeightConstraint is nil!");
        return;
    }
    if (!self.fillView) {
        NSLog(@"[JeevesLightToggleCell] fillView is nil!");
        return;
    }

    CGFloat cellHeight = self.contentView.bounds.size.height;
    if (cellHeight <= 0) {
        NSLog(@"[JeevesLightToggleCell] cellHeight is %f, skipping", cellHeight);
        return;
    }

    // Clamp brightness to valid range
    if (brightness < 0) brightness = 0;
    if (brightness > 100) brightness = 100;

    CGFloat fillHeight = (brightness / 100.0) * cellHeight;
    self.fillHeightConstraint.constant = fillHeight;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // X-Small cards are half height: one-line name and a smaller status.
    // Only assign on change, since changing fonts triggers another layout pass.
    BOOL shortCard = self.contentView.bounds.size.height < 110;
    NSInteger nameLines = shortCard ? 1 : 2;
    if (self.nameLabel.numberOfLines != nameLines) self.nameLabel.numberOfLines = nameLines;
    CGFloat statusSize = shortCard ? 24 : 32;
    if (self.statusLabel.font.pointSize != statusSize) self.statusLabel.font = [UIFont boldSystemFontOfSize:statusSize];

    [self updateLightControls];
    // Don't update fill during pan gesture - it causes flickering
    if (self.isPanning) return;

    // Skip if cell is not yet configured (entityId is nil after prepareForReuse)
    if (!self.entityId) return;

    // Update fill height when cell size changes using cached values
    // This avoids accessing potentially-deallocated entity objects
    if (self.cachedIsOn && self.isDimmable) {
        [self updateFillForBrightness:self.cachedBrightness];
    } else if (self.cachedIsOn) {
        [self updateFillForBrightness:100];
    }
}

- (void)flashHighlight {
    [[self class] flashTapFeedbackOnLayer:self.contentView.layer];
}

+ (void)flashTapFeedbackOnLayer:(CALayer *)layer {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UIColor *glowColor = [theme onColor];

    // Set up border
    layer.borderWidth = 6.0;

    // Fade in
    CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    fadeIn.fromValue = (__bridge id)[UIColor clearColor].CGColor;
    fadeIn.toValue = (__bridge id)glowColor.CGColor;
    fadeIn.duration = 0.1;
    fadeIn.beginTime = 0;

    // Fade out
    CABasicAnimation *fadeOut = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    fadeOut.fromValue = (__bridge id)glowColor.CGColor;
    fadeOut.toValue = (__bridge id)[UIColor clearColor].CGColor;
    fadeOut.duration = 0.1;
    fadeOut.beginTime = 0.1;

    // Group animations
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[fadeIn, fadeOut];
    group.duration = 0.2;
    group.fillMode = kCAFillModeForwards;
    group.removedOnCompletion = NO;

    [layer addAnimation:group forKey:@"flashBorder"];
    layer.borderColor = [UIColor clearColor].CGColor;
}

- (void)toggleTapped {
    NSLog(@"[JeevesLightToggleCell] toggleTapped called");

    // Flash highlight animation
    [self flashHighlight];

    // Skip if read-only sensor
    if (self.isReadOnly) {
        if ([self.delegate respondsToSelector:@selector(lightToggleCellDidTapReadOnlyEntity:)]) {
            [self.delegate lightToggleCellDidTapReadOnlyEntity:self];
        }
        return;
    }

    // Use cached entityId - don't rely on entity being present since it's weak
    NSString *entityId = self.entityId;
    if (!entityId) {
        NSLog(@"[JeevesLightToggleCell] entityId is nil, returning");
        return;
    }

    // Handle scripts - trigger instead of toggle
    if (self.isScript) {
        NSLog(@"[JeevesLightToggleCell] script entity, triggering: %@", entityId);
        HAEntity *entity = self.entity;
        if (self.delegate && [self.delegate respondsToSelector:@selector(lightToggleCell:didTriggerScript:)]) {
            [self.delegate lightToggleCell:self didTriggerScript:entity];
        }
        return;
    }

    // Use cached state
    BOOL currentState = self.cachedIsOn;
    BOOL newState = !currentState;

    NSLog(@"[JeevesLightToggleCell] entityId: %@, cachedIsOn: %d, newState: %d", entityId, currentState, newState);

    // Update cached state immediately for responsive UI
    self.cachedIsOn = newState;

    // Try to get entity for delegate - it might be nil if already deallocated
    HAEntity *entity = self.entity;

    // Call delegate directly - no dispatch needed since tap gesture is already on main thread
    NSLog(@"[JeevesLightToggleCell] about to call delegate");
    if (self.delegate && [self.delegate respondsToSelector:@selector(lightToggleCell:didToggleEntity:toState:)]) {
        NSLog(@"[JeevesLightToggleCell] calling delegate method");
        // Pass entity (might be nil) - delegate should handle nil case
        [self.delegate lightToggleCell:self didToggleEntity:entity toState:newState];
        NSLog(@"[JeevesLightToggleCell] delegate method returned");
    }
    NSLog(@"[JeevesLightToggleCell] toggleTapped returning");
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    // Skip read-only sensors entirely
    if (self.isReadOnly) {
        return;
    }

    // Only dimmable lights start this gesture (see gestureRecognizerShouldBegin:)
    if (!self.entityId || !self.isDimmable) {
        return;
    }

    CGFloat cellHeight = self.contentView.bounds.size.height;

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.isPanning = YES;
        self.panStartY = [pan locationInView:self.contentView].y;
        // Start at current brightness using cached value, minimum 1%
        self.panStartBrightness = self.cachedIsOn ? MAX(1, self.cachedBrightness) : 1;
        self.lastBrightnessUpdateTime = 0;
        self.lastSentBrightness = -1;

        // Notify delegate that interaction started
        if (self.delegate && [self.delegate respondsToSelector:@selector(lightToggleCell:didChangeInteractionState:)]) {
            [self.delegate lightToggleCell:self didChangeInteractionState:YES];
        }
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat currentY = [pan locationInView:self.contentView].y;
        // Moving up increases brightness, moving down decreases
        CGFloat deltaY = self.panStartY - currentY;
        CGFloat deltaBrightness = (deltaY / cellHeight) * 100.0;
        CGFloat newBrightness = self.panStartBrightness + deltaBrightness;

        // Clamp between 1 and 100 (1% minimum)
        newBrightness = MAX(1, MIN(100, newBrightness));
        NSInteger brightnessInt = (NSInteger)newBrightness;

        // Update display in real-time
        self.statusLabel.text = [NSString stringWithFormat:@"%ld%%", (long)brightnessInt];
        [self updateFillForBrightness:brightnessInt];

        // Show fill view if it was hidden
        self.fillView.hidden = NO;

        JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
        self.statusLabel.textColor = [theme onColor];
        self.nameLabel.textColor = [theme textColor];

        // Send throttled brightness updates every 150ms
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - self.lastBrightnessUpdateTime >= 0.150 && brightnessInt != self.lastSentBrightness) {
            self.lastBrightnessUpdateTime = now;
            self.lastSentBrightness = brightnessInt;

            HAEntity *entity = self.entity;
            if (self.delegate && [self.delegate respondsToSelector:@selector(lightToggleCell:didSetBrightness:forEntity:)]) {
                [self.delegate lightToggleCell:self didSetBrightness:brightnessInt forEntity:entity];
            }
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        self.isPanning = NO;

        // Notify delegate that interaction ended
        if (self.delegate && [self.delegate respondsToSelector:@selector(lightToggleCell:didChangeInteractionState:)]) {
            [self.delegate lightToggleCell:self didChangeInteractionState:NO];
        }

        // Get final brightness value from display
        NSString *text = self.statusLabel.text;
        NSInteger brightness = [[text stringByReplacingOccurrencesOfString:@"%" withString:@""] integerValue];

        if (brightness < 1) brightness = 1;

        // Update cached brightness
        self.cachedBrightness = brightness;
        self.cachedIsOn = YES;

        // Send brightness change - entity might be nil (weak reference)
        HAEntity *entity = self.entity;
        if (self.delegate && [self.delegate respondsToSelector:@selector(lightToggleCell:didSetBrightness:forEntity:)]) {
            [self.delegate lightToggleCell:self didSetBrightness:brightness forEntity:entity];
        }
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (self.isPanning) return;

    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UIColor *glowColor = [theme onColor];

    // Set up border on contentView (which has the corner radius)
    self.contentView.layer.borderWidth = 6.0;

    // Animate border color opacity (fade in/out over 100ms each)
    CGColorRef fromColor = highlighted ? [UIColor clearColor].CGColor : glowColor.CGColor;
    CGColorRef toColor = highlighted ? glowColor.CGColor : [UIColor clearColor].CGColor;

    CABasicAnimation *borderAnim = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    borderAnim.fromValue = (__bridge id)fromColor;
    borderAnim.toValue = (__bridge id)toColor;
    borderAnim.duration = 0.1; // 100ms
    borderAnim.fillMode = kCAFillModeForwards;
    borderAnim.removedOnCompletion = NO;

    [self.contentView.layer addAnimation:borderAnim forKey:@"borderColor"];
    self.contentView.layer.borderColor = toColor;
}

@end
