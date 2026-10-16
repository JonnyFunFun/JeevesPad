#import "JeevesMaintenance.h"
#import "JeevesGuidedAccess.h"
#import "JeevesIconView.h"
#import "JeevesThemeManager.h"

static NSString * const kDefaultsActive  = @"JeevesMaintenanceActive";   // per iPad, not shared
static NSString * const kDefaultsMessage = @"JeevesMaintenanceMessage";
static const NSUInteger kMaxMessageLength = 500;
static const NSUInteger kAttemptsBeforeLockout = 5;
static const NSTimeInterval kLockout = 60;
static const NSTimeInterval kUnlockHold = 5;

#pragma mark - Notice

// The notice: an icon, a title and the message, centred; laid out by hand (iOS 9 stack
// views with centre alignment crash on dealloc)
@interface JeevesMaintenanceView : UIView
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation JeevesMaintenanceView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
        self.backgroundColor = [theme backgroundColor];
        _icon = [[UIImageView alloc] initWithImage:[JeevesIconView imageWithIconType:JeevesIconTypeGear
                                                                                size:CGSizeMake(88, 88)
                                                                               color:[theme onColor]]];
        _titleLabel = [self labelWithFont:[UIFont systemFontOfSize:40 weight:UIFontWeightSemibold] color:[theme textColor]];
        _titleLabel.text = @"Under Maintenance";
        _messageLabel = [self labelWithFont:[UIFont systemFontOfSize:22] color:[theme secondaryTextColor]];
        _footerLabel = [self labelWithFont:[UIFont systemFontOfSize:14] color:[theme secondaryTextColor]];
        _footerLabel.text = [UIDevice currentDevice].name;
        for (UIView *view in @[_icon, _titleLabel, _messageLabel, _footerLabel]) [self addSubview:view];
    }
    return self;
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(self.bounds.size.width - 48, 640);
    CGFloat x = (self.bounds.size.width - width) / 2;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGSize messageSize = [self.messageLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat total = 88 + 28 + titleSize.height + 16 + messageSize.height;
    CGFloat y = MAX(24, (self.bounds.size.height - total) / 2);
    self.icon.frame = CGRectMake((self.bounds.size.width - 88) / 2, y, 88, 88);
    y += 88 + 28;
    self.titleLabel.frame = CGRectMake(x, y, width, titleSize.height);
    y += titleSize.height + 16;
    self.messageLabel.frame = CGRectMake(x, y, width, messageSize.height);
    self.footerLabel.frame = CGRectMake(x, self.bounds.size.height - 44, width, 20);
}

@end

@interface JeevesMaintenanceViewController : UIViewController
@property (nonatomic, strong) JeevesMaintenanceView *notice;
@property (nonatomic, assign) NSUInteger failedAttempts;
@property (nonatomic, strong) NSDate *lockedUntil;
@end

@implementation JeevesMaintenanceViewController

- (void)loadView {
    self.notice = [[JeevesMaintenanceView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view = self.notice;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.minimumPressDuration = kUnlockHold;
    [self.view addGestureRecognizer:hold];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || self.presentedViewController) return;
    NSString *code = [JeevesGuidedAccess sharedManager].unlockCode;
    if (!code) {
        [self showMessage:@"Maintenance mode can only be turned off from Home Assistant." title:@"Under Maintenance"];
        return;
    }
    if (self.lockedUntil && [self.lockedUntil timeIntervalSinceNow] > 0) {
        [self showMessage:@"Too many wrong codes. Try again in a minute." title:@"Locked"];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"End Maintenance"
                                                                   message:@"Enter the unlock code."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.keyboardType = UIKeyboardTypeNumberPad;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"End" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *entered = weakAlert.textFields.firstObject.text ?: @"";
        if ([entered isEqualToString:code]) {
            self.failedAttempts = 0;
            [[JeevesMaintenance sharedManager] setActive:NO message:nil];
            return;
        }
        if (++self.failedAttempts >= kAttemptsBeforeLockout) {
            self.failedAttempts = 0;
            self.lockedUntil = [NSDate dateWithTimeIntervalSinceNow:kLockout];
        }
        [self showMessage:nil title:@"Wrong Code"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Manager

@interface JeevesMaintenance ()
@property (nonatomic, strong) UIWindow *window;
@end

@implementation JeevesMaintenance

+ (instancetype)sharedManager {
    static JeevesMaintenance *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

+ (NSString *)defaultMessage {
    return @"This panel is being looked after and will be back shortly.";
}

- (BOOL)isActive {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsActive];
}

- (NSString *)message {
    NSString *message = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsMessage];
    return message.length > 0 ? message : [[self class] defaultMessage];
}

- (void)start {
    if (self.active) [self showNotice];
}

- (void)setActive:(BOOL)active message:(NSString *)message {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *trimmed = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > kMaxMessageLength) trimmed = [trimmed substringToIndex:kMaxMessageLength];
    if (trimmed.length > 0) [defaults setObject:trimmed forKey:kDefaultsMessage];
    else if (active) [defaults removeObjectForKey:kDefaultsMessage];
    [defaults setBool:active forKey:kDefaultsActive];
    [defaults synchronize];
    if (active) [self showNotice]; else [self hideNotice];
    NSLog(@"[Maintenance] %@", active ? @"On" : @"Off");
}

- (void)showNotice {
    if (!self.window) {
        self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.window.windowLevel = UIWindowLevelAlert + 1; // above everything, including alerts
        self.window.rootViewController = [[JeevesMaintenanceViewController alloc] init];
    }
    JeevesMaintenanceViewController *controller = (JeevesMaintenanceViewController *)self.window.rootViewController;
    [controller loadViewIfNeeded];
    controller.notice.messageLabel.text = self.message;
    [controller.notice setNeedsLayout];
    self.window.hidden = NO;
}

- (void)hideNotice {
    self.window.hidden = YES;
    self.window = nil;
    // Give the app's own window back the keyboard and status bar
    [[UIApplication sharedApplication].delegate.window makeKeyAndVisible];
}

@end
