#import "JeevesEntityMoreInfoViewController.h"
#import "HAEntity.h"
#import "HAAPIClient.h"
#import "JeevesThemeManager.h"
#import "JeevesLightControlsView.h"
#import "JeevesCardSettings.h"

static const NSTimeInterval kRefreshInterval = 2.0;
// After the user changes a control, ignore server state for that control briefly
// so the UI doesn't snap back before Home Assistant reports the new state.
static const NSTimeInterval kControlLockInterval = 2.5;

@interface JeevesEntityMoreInfoViewController () <UITextFieldDelegate>
@property (nonatomic, strong) HAEntity *entity;
@property (nonatomic, copy) NSString *dashboardID;
@property (nonatomic, strong) UITextField *cardNameField;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSDate *controlsLockedUntil;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UILabel *lastChangedLabel;
@property (nonatomic, strong) UIStackView *attributesStack;

// Type-specific controls (only those relevant to the entity are created)
@property (nonatomic, strong) UISwitch *powerSwitch;
@property (nonatomic, strong) JeevesLightControlsView *lightControls; // brightness, color, temperature, effect
@property (nonatomic, strong) UILabel *valueLabel;       // climate target temperature / number value
@property (nonatomic, strong) UIButton *optionButton;    // select option / climate HVAC mode
@end

@implementation JeevesEntityMoreInfoViewController

- (instancetype)initWithEntity:(HAEntity *)entity dashboardID:(NSString *)dashboardID {
    self = [super init];
    if (self) {
        _entity = entity;
        _dashboardID = [dashboardID copy];
        self.title = entity.friendlyName;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.view.backgroundColor = [theme backgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 12.0;
    [self.scrollView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor      constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stackView.topAnchor      constraintEqualToAnchor:self.scrollView.topAnchor constant:12],
        [self.stackView.bottomAnchor   constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-12],
        [self.stackView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
    ]];

    [self buildStateSection];
    [self buildCardSection];
    [self buildControlsSection];
    [self buildAttributesSection];
    [self applyEntity:self.entity];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:kRefreshInterval
                                                         target:self
                                                       selector:@selector(refresh)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveCardName];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refresh {
    [[HAAPIClient sharedClient] fetchStateForEntity:self.entity.entityId completion:^(HAEntity *entity, NSError *error) {
        if (entity) [self applyEntity:entity];
    }];
}

#pragma mark - Building

- (UIView *)cardWithViews:(NSArray<UIView *> *)views {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [[JeevesThemeManager sharedManager] cardBackgroundColor];
    card.layer.cornerRadius = 12;

    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:views];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 8;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor      constraintEqualToAnchor:card.topAnchor constant:12],
        [inner.bottomAnchor   constraintEqualToAnchor:card.bottomAnchor constant:-12],
        [inner.leadingAnchor  constraintEqualToAnchor:card.leadingAnchor constant:12],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
    ]];
    [self.stackView addArrangedSubview:card];
    return card;
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

// Title on the left, control on the right, both vertically centered. Built with plain
// constraints: a center-aligned UIStackView crashes on iOS 9 when it's deallocated
// ("-[_UILayoutSpacer _didRemoveDependentConstraint:]: unrecognized selector").
- (UIView *)rowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *label = [self labelWithFont:[UIFont systemFontOfSize:17] color:[[JeevesThemeManager sharedManager] textColor]];
    label.text = title;
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    control.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *row = [[UIView alloc] init];
    [row addSubview:label];
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12],
        [control.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor],
        [control.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[theme textColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    button.backgroundColor = [theme secondaryBackgroundColor];
    button.layer.cornerRadius = 8;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 16);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIStackView *)horizontalStackWithViews:(NSArray<UIView *> *)views {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 12;
    return stack;
}

- (void)buildStateSection {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.stateLabel = [self labelWithFont:[UIFont boldSystemFontOfSize:34] color:[theme textColor]];
    self.lastChangedLabel = [self labelWithFont:[UIFont systemFontOfSize:14] color:[theme secondaryTextColor]];
    UILabel *idLabel = [self labelWithFont:[UIFont systemFontOfSize:13] color:[theme secondaryTextColor]];
    idLabel.text = self.entity.entityId;
    [self cardWithViews:@[self.stateLabel, self.lastChangedLabel, idLabel]];
}

// Name and size of the dashboard card this screen was opened from
- (void)buildCardSection {
    if (!self.dashboardID) return;
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    JeevesCardSettings *settings = [JeevesCardSettings sharedSettings];

    UILabel *header = [self labelWithFont:[UIFont boldSystemFontOfSize:17] color:[theme textColor]];
    header.text = @"Card";

    self.cardNameField = [[UITextField alloc] init];
    self.cardNameField.text = [settings customNameForEntityId:self.entity.entityId dashboard:self.dashboardID];
    self.cardNameField.textColor = [theme textColor];
    self.cardNameField.backgroundColor = [theme secondaryBackgroundColor];
    self.cardNameField.layer.cornerRadius = 8;
    self.cardNameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 44)];
    self.cardNameField.leftViewMode = UITextFieldViewModeAlways;
    self.cardNameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.cardNameField.returnKeyType = UIReturnKeyDone;
    self.cardNameField.delegate = self;
    // Placeholder shows the Home Assistant name, which is used when this is empty
    self.cardNameField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:self.entity.friendlyName ?: @""
                                        attributes:@{NSForegroundColorAttributeName: [theme secondaryTextColor]}];
    [self.cardNameField.heightAnchor constraintEqualToConstant:44].active = YES;

    NSArray<NSNumber *> *sizes = [JeevesCardSettings orderedSizes];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSNumber *size in sizes) [titles addObject:[JeevesCardSettings titleForSize:size.integerValue]];
    UISegmentedControl *sizeControl = [[UISegmentedControl alloc] initWithItems:titles];
    sizeControl.selectedSegmentIndex = [sizes indexOfObject:@([settings sizeForEntityId:self.entity.entityId dashboard:self.dashboardID])];
    sizeControl.tintColor = [theme onColor];
    [sizeControl addTarget:self action:@selector(cardSizeChanged:) forControlEvents:UIControlEventValueChanged];
    [sizeControl.heightAnchor constraintEqualToConstant:36].active = YES;

    [self cardWithViews:@[header,
                          [self rowWithTitle:@"Name" control:self.cardNameField],
                          [self rowWithTitle:@"Size" control:sizeControl]]];
    [self.cardNameField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
}

- (void)saveCardName {
    if (!self.cardNameField) return;
    [[JeevesCardSettings sharedSettings] setCustomName:self.cardNameField.text
                                           forEntityId:self.entity.entityId
                                             dashboard:self.dashboardID];
}

- (void)cardSizeChanged:(UISegmentedControl *)control {
    JeevesCardSize size = [[JeevesCardSettings orderedSizes][control.selectedSegmentIndex] integerValue];
    [[JeevesCardSettings sharedSettings] setSize:size
                                     forEntityId:self.entity.entityId
                                       dashboard:self.dashboardID];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self saveCardName];
}

- (void)buildControlsSection {
    NSMutableArray<UIView *> *controls = [NSMutableArray array];

    switch (self.entity.entityType) {
        case HAEntityTypeLight:
        case HAEntityTypeSwitch:
        case HAEntityTypeInputBoolean:
        case HAEntityTypeFan: {
            self.powerSwitch = [[UISwitch alloc] init];
            self.powerSwitch.onTintColor = [[JeevesThemeManager sharedManager] onColor];
            [self.powerSwitch addTarget:self action:@selector(powerSwitchChanged) forControlEvents:UIControlEventValueChanged];
            [controls addObject:[self rowWithTitle:@"Power" control:self.powerSwitch]];

            if ([JeevesLightControlsView compactRowCountForEntity:self.entity showsBrightness:YES] > 0) {
                self.lightControls = [[JeevesLightControlsView alloc] initWithStyle:JeevesLightControlsStyleFull];
                [self.lightControls configureWithEntity:self.entity];
                [controls addObject:self.lightControls];
            }
            break;
        }
        case HAEntityTypeScript:
            [controls addObject:[self buttonWithTitle:@"Run" action:@selector(runTapped)]];
            break;
        case HAEntityTypeButton:
            [controls addObject:[self buttonWithTitle:@"Press" action:@selector(runTapped)]];
            break;
        case HAEntityTypeVacuum:
            [controls addObject:[self horizontalStackWithViews:@[
                [self buttonWithTitle:@"Start" action:@selector(vacuumStartTapped)],
                [self buttonWithTitle:@"Pause" action:@selector(vacuumPauseTapped)],
                [self buttonWithTitle:@"Dock" action:@selector(vacuumDockTapped)],
            ]]];
            break;
        case HAEntityTypeClimate:
        case HAEntityTypeNumber: {
            self.valueLabel = [self labelWithFont:[UIFont boldSystemFontOfSize:28] color:[[JeevesThemeManager sharedManager] textColor]];
            self.valueLabel.textAlignment = NSTextAlignmentCenter;
            [controls addObject:[self horizontalStackWithViews:@[
                [self buttonWithTitle:@"−" action:@selector(decrementTapped)],
                self.valueLabel,
                [self buttonWithTitle:@"+" action:@selector(incrementTapped)],
            ]]];
            if (self.entity.entityType == HAEntityTypeClimate) {
                self.optionButton = [self buttonWithTitle:@"Mode" action:@selector(optionTapped)];
                [controls addObject:[self rowWithTitle:@"Mode" control:self.optionButton]];
            }
            break;
        }
        case HAEntityTypeSelect:
            self.optionButton = [self buttonWithTitle:@"Option" action:@selector(optionTapped)];
            [controls addObject:[self rowWithTitle:@"Option" control:self.optionButton]];
            break;
        default:
            break;
    }

    if (controls.count > 0) [self cardWithViews:controls];
}

- (void)buildAttributesSection {
    UILabel *header = [self labelWithFont:[UIFont boldSystemFontOfSize:17] color:[[JeevesThemeManager sharedManager] textColor]];
    header.text = @"Attributes";
    self.attributesStack = [[UIStackView alloc] init];
    self.attributesStack.axis = UILayoutConstraintAxisVertical;
    self.attributesStack.spacing = 6;
    [self cardWithViews:@[header, self.attributesStack]];
}

#pragma mark - Applying state

- (BOOL)controlsLocked {
    return self.controlsLockedUntil && [self.controlsLockedUntil timeIntervalSinceNow] > 0;
}

- (void)lockControls {
    self.controlsLockedUntil = [NSDate dateWithTimeIntervalSinceNow:kControlLockInterval];
}

- (void)applyEntity:(HAEntity *)entity {
    self.entity = entity;
    self.title = entity.friendlyName;
    self.stateLabel.text = [self formattedStateForEntity:entity];
    self.lastChangedLabel.text = entity.lastChanged
        ? [NSString stringWithFormat:@"Last changed %@", [self relativeTimeSince:entity.lastChanged]]
        : nil;
    // Avoid needless relayout of the stack view on every refresh
    BOOL hideLastChanged = (entity.lastChanged == nil);
    if (self.lastChangedLabel.hidden != hideLastChanged) {
        self.lastChangedLabel.hidden = hideLastChanged;
    }

    if (![self controlsLocked]) {
        self.powerSwitch.on = [entity isOn];
        if (self.valueLabel) {
            self.valueLabel.text = [self formatNumber:[self currentAdjustableValue]];
        }
        if (self.optionButton) {
            // A select's state is its option; a climate entity's state is its HVAC mode
            [self.optionButton setTitle:[self displayString:entity.state] forState:UIControlStateNormal];
        }
    }

    [self.lightControls configureWithEntity:entity];
    [self rebuildAttributes];
}

- (void)rebuildAttributes {
    for (UIView *v in [self.attributesStack.arrangedSubviews copy]) {
        [self.attributesStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    NSSet *hidden = [NSSet setWithArray:@[@"friendly_name", @"icon", @"entity_picture"]];
    NSArray *keys = [[self.entity.attributes allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        if ([hidden containsObject:key]) continue;
        UILabel *name = [self labelWithFont:[UIFont systemFontOfSize:15] color:[theme secondaryTextColor]];
        name.text = [self displayString:key];
        UILabel *value = [self labelWithFont:[UIFont systemFontOfSize:15] color:[theme textColor]];
        value.text = [self stringForAttributeValue:self.entity.attributes[key]];
        value.textAlignment = NSTextAlignmentRight;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[name, value]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.distribution = UIStackViewDistributionFillEqually;
        [self.attributesStack addArrangedSubview:row];
    }
    if (self.attributesStack.arrangedSubviews.count == 0) {
        UILabel *none = [self labelWithFont:[UIFont systemFontOfSize:15] color:[theme secondaryTextColor]];
        none.text = @"No attributes";
        [self.attributesStack addArrangedSubview:none];
    }
}

#pragma mark - Formatting

- (NSString *)displayString:(NSString *)raw {
    if (![raw isKindOfClass:[NSString class]] || raw.length == 0) return @"";
    NSString *spaced = [raw stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    return [[[spaced substringToIndex:1] uppercaseString] stringByAppendingString:[spaced substringFromIndex:1]];
}

- (NSString *)formattedStateForEntity:(HAEntity *)entity {
    NSString *state = entity.state ?: @"unknown";
    NSString *unit = entity.attributes[@"unit_of_measurement"];
    if ([unit isKindOfClass:[NSString class]] && unit.length > 0) {
        return [NSString stringWithFormat:@"%@ %@", state, unit];
    }
    return [self displayString:state];
}

- (NSString *)stringForAttributeValue:(id)value {
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id item in value) [parts addObject:[self stringForAttributeValue:item]];
        return [parts componentsJoinedByString:@", "];
    }
    if ([value isKindOfClass:[NSNumber class]]) return [self formatNumber:[value doubleValue]];
    if ([value isKindOfClass:[NSNull class]]) return @"—";
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
        return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : [value description];
    }
    return [value description];
}

- (NSString *)formatNumber:(double)number {
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = 2;
    });
    return [formatter stringFromNumber:@(number)];
}

- (NSString *)relativeTimeSince:(NSDate *)date {
    NSTimeInterval seconds = MAX(0, -[date timeIntervalSinceNow]);
    if (seconds < 60)    return @"just now";
    if (seconds < 3600)  return [NSString stringWithFormat:@"%ld min ago", (long)(seconds / 60)];
    if (seconds < 86400) return [NSString stringWithFormat:@"%ld h ago", (long)(seconds / 3600)];
    return [NSString stringWithFormat:@"%ld days ago", (long)(seconds / 86400)];
}

#pragma mark - Service calls

- (NSString *)domain {
    return [[self.entity.entityId componentsSeparatedByString:@"."] firstObject];
}

- (void)callService:(NSString *)service parameters:(NSDictionary *)parameters {
    [[HAAPIClient sharedClient] callService:[self domain] service:service entityId:self.entity.entityId parameters:parameters completion:^(BOOL success, id result, NSError *error) {
        if (!success) {
            NSLog(@"[MoreInfo] %@.%@ failed for %@: %@", [self domain], service, self.entity.entityId, error);
        }
        [self refresh];
    }];
}

- (void)powerSwitchChanged {
    [self lockControls];
    if (self.powerSwitch.on) {
        [[HAAPIClient sharedClient] turnOnEntity:self.entity.entityId completion:^(BOOL s, id r, NSError *e) { [self refresh]; }];
    } else {
        [[HAAPIClient sharedClient] turnOffEntity:self.entity.entityId completion:^(BOOL s, id r, NSError *e) { [self refresh]; }];
    }
}

- (void)runTapped {
    // Scripts run via turn_on; turnOnEntity maps buttons to button.press
    [[HAAPIClient sharedClient] turnOnEntity:self.entity.entityId completion:^(BOOL s, id r, NSError *e) { [self refresh]; }];
}

- (void)vacuumStartTapped { [self callService:@"start" parameters:nil]; }
- (void)vacuumPauseTapped { [self callService:@"pause" parameters:nil]; }
- (void)vacuumDockTapped  { [self callService:@"return_to_base" parameters:nil]; }

#pragma mark - Climate / number

- (double)numberAttribute:(NSString *)key fallback:(double)fallback {
    id v = self.entity.attributes[key];
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : fallback;
}

- (double)currentAdjustableValue {
    if (self.entity.entityType == HAEntityTypeClimate) {
        return [self numberAttribute:@"temperature" fallback:0];
    }
    return [self.entity.state doubleValue];
}

- (void)adjustValueBySteps:(NSInteger)steps {
    BOOL climate = (self.entity.entityType == HAEntityTypeClimate);
    double step = [self numberAttribute:(climate ? @"target_temp_step" : @"step") fallback:(climate ? 0.5 : 1)];
    double min  = [self numberAttribute:(climate ? @"min_temp" : @"min") fallback:-DBL_MAX];
    double max  = [self numberAttribute:(climate ? @"max_temp" : @"max") fallback:DBL_MAX];

    // Base on what's displayed so repeated taps accumulate before HA reports back
    double current = [[self.valueLabel.text stringByReplacingOccurrencesOfString:@"," withString:@""] doubleValue];
    double value = MIN(max, MAX(min, current + steps * step));
    self.valueLabel.text = [self formatNumber:value];
    [self lockControls];

    if (climate) {
        [self callService:@"set_temperature" parameters:@{@"temperature": @(value)}];
    } else {
        [self callService:@"set_value" parameters:@{@"value": @(value)}];
    }
}

- (void)decrementTapped { [self adjustValueBySteps:-1]; }
- (void)incrementTapped { [self adjustValueBySteps:1]; }

#pragma mark - Select / HVAC mode

- (void)optionTapped {
    BOOL climate = (self.entity.entityType == HAEntityTypeClimate);
    NSArray *options = self.entity.attributes[climate ? @"hvac_modes" : @"options"];
    if (![options isKindOfClass:[NSArray class]] || options.count == 0) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:(climate ? @"Mode" : @"Option")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (id option in options) {
        NSString *value = [option description];
        NSString *title = [self displayString:value];
        if ([value isEqualToString:self.entity.state]) title = [NSString stringWithFormat:@"✓ %@", title];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self lockControls];
            [self.optionButton setTitle:[self displayString:value] forState:UIControlStateNormal];
            if (climate) {
                [self callService:@"set_hvac_mode" parameters:@{@"hvac_mode": value}];
            } else {
                [self callService:@"select_option" parameters:@{@"option": value}];
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.optionButton;
    sheet.popoverPresentationController.sourceRect = self.optionButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
