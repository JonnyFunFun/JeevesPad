#import "SettingsViewController.h"
#import "HAAPIClient.h"
#import "JeevesDashboardViewController.h"
#import "JeevesThemeManager.h"
#import "JeevesBatteryReporter.h"
#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinTarget.h"

@interface SettingsViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *accessTokenField;
@property (nonatomic, strong) UISwitch *batteryReportingSwitch;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *testConnectionButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Jellyfin
@property (nonatomic, strong) UISwitch    *jellyfinEnabledSwitch;
@property (nonatomic, strong) UITextField *jellyfinServerURLField;
@property (nonatomic, strong) UITextField *jellyfinUsernameField;
@property (nonatomic, strong) UITextField *jellyfinPasswordField;
@property (nonatomic, strong) UIButton    *jellyfinSignInButton;
@property (nonatomic, strong) UIButton    *jellyfinTargetButton;
@property (nonatomic, strong) UILabel     *jellyfinStatusLabel;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Settings";

    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.view.backgroundColor = [theme backgroundColor];

    if (!self.isInitialSetup) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    }

    [self setupUI];
    [self loadSavedSettings];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
    [self.scrollView addSubview:self.contentView];

    CGFloat padding = 20.0;
    CGFloat yOffset = 80.0;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 30)];
    titleLabel.text = @"Home Assistant Setup";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [theme textColor];
    [self.contentView addSubview:titleLabel];
    yOffset += 50;

    UILabel *urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 20)];
    urlLabel.text = @"Base URL (e.g., http://192.168.1.x:8123)";
    urlLabel.font = [UIFont systemFontOfSize:14];
    urlLabel.textColor = [theme secondaryTextColor];
    [self.contentView addSubview:urlLabel];
    yOffset += 25;

    self.baseURLField = [[UITextField alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 44)];
    self.baseURLField.backgroundColor = [theme cardBackgroundColor];
    self.baseURLField.textColor = [theme textColor];
    self.baseURLField.layer.cornerRadius = 8;
    self.baseURLField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 44)];
    self.baseURLField.leftViewMode = UITextFieldViewModeAlways;
    self.baseURLField.placeholder = @"http://192.168.1.x:8123";
    self.baseURLField.keyboardType = UIKeyboardTypeURL;
    self.baseURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.baseURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.baseURLField.delegate = self;
    [self.contentView addSubview:self.baseURLField];
    yOffset += 60;

    UILabel *tokenLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 20)];
    tokenLabel.text = @"Long-Lived Access Token";
    tokenLabel.font = [UIFont systemFontOfSize:14];
    tokenLabel.textColor = [theme secondaryTextColor];
    [self.contentView addSubview:tokenLabel];
    yOffset += 25;

    self.accessTokenField = [[UITextField alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 44)];
    self.accessTokenField.backgroundColor = [theme cardBackgroundColor];
    self.accessTokenField.textColor = [theme textColor];
    self.accessTokenField.layer.cornerRadius = 8;
    self.accessTokenField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 44)];
    self.accessTokenField.leftViewMode = UITextFieldViewModeAlways;
    self.accessTokenField.placeholder = @"Enter access token";
    self.accessTokenField.secureTextEntry = YES;
    self.accessTokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.accessTokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.accessTokenField.delegate = self;
    [self.contentView addSubview:self.accessTokenField];
    yOffset += 60;

    // Battery reporting section
    UIView *batteryRow = [[UIView alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 44)];
    batteryRow.backgroundColor = [theme cardBackgroundColor];
    batteryRow.layer.cornerRadius = 8;
    [self.contentView addSubview:batteryRow];

    UILabel *batteryLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, batteryRow.bounds.size.width - 70, 44)];
    batteryLabel.text = @"Battery Reporting";
    batteryLabel.font = [UIFont systemFontOfSize:16];
    batteryLabel.textColor = [theme textColor];
    [batteryRow addSubview:batteryLabel];

    self.batteryReportingSwitch = [[UISwitch alloc] init];
    self.batteryReportingSwitch.frame = CGRectMake(batteryRow.bounds.size.width - 60, 7, 51, 31);
    self.batteryReportingSwitch.onTintColor = [theme accentColor];
    [batteryRow addSubview:self.batteryReportingSwitch];
    yOffset += 50;

    UILabel *batteryHintLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 52)];
    batteryHintLabel.text = [NSString stringWithFormat:@"Reports battery level to Home Assistant for smart plug automation. See README for setup.\nWebhook ID: %@",
                             [JeevesBatteryReporter sharedReporter].webhookID];
    batteryHintLabel.font = [UIFont systemFontOfSize:12];
    batteryHintLabel.textColor = [theme secondaryTextColor];
    batteryHintLabel.numberOfLines = 0;
    [self.contentView addSubview:batteryHintLabel];
    yOffset += 56;

    // Debug: Show current battery status
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    UIDevice *device = [UIDevice currentDevice];
    float batteryLevel = device.batteryLevel;
    UIDeviceBatteryState state = device.batteryState;
    NSString *stateStr = @"unknown";
    if (state == UIDeviceBatteryStateCharging) stateStr = @"charging";
    else if (state == UIDeviceBatteryStateFull) stateStr = @"full";
    else if (state == UIDeviceBatteryStateUnplugged) stateStr = @"unplugged";

    NSInteger percent = (state == UIDeviceBatteryStateFull) ? 100 : (batteryLevel >= 0 ? (NSInteger)(batteryLevel * 100) : -1);

    UILabel *batteryDebugLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 20)];
    batteryDebugLabel.text = [NSString stringWithFormat:@"Battery: %ld%% (raw: %.2f, state: %@)", (long)percent, batteryLevel, stateStr];
    batteryDebugLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    batteryDebugLabel.textColor = [theme secondaryTextColor];
    [self.contentView addSubview:batteryDebugLabel];
    yOffset += 30;

    self.testConnectionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testConnectionButton.frame = CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 44);
    [self.testConnectionButton setTitle:@"Test Connection" forState:UIControlStateNormal];
    [self.testConnectionButton setTitleColor:[theme accentColor] forState:UIControlStateNormal];
    self.testConnectionButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.testConnectionButton addTarget:self action:@selector(testConnectionTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.testConnectionButton];
    yOffset += 54;

    // --- Jellyfin section ---
    CGFloat fieldWidth = self.view.bounds.size.width - 2 * padding;

    UILabel *jellyfinHeader = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, fieldWidth, 28)];
    jellyfinHeader.text = @"Jellyfin";
    jellyfinHeader.font = [UIFont boldSystemFontOfSize:18];
    jellyfinHeader.textColor = [theme textColor];
    [self.contentView addSubview:jellyfinHeader];
    yOffset += 36;

    UIView *jellyfinRow = [[UIView alloc] initWithFrame:CGRectMake(padding, yOffset, fieldWidth, 44)];
    UILabel *jellyfinLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, jellyfinRow.bounds.size.width - 70, 44)];
    jellyfinLbl.text = @"Enable Jellyfin";
    jellyfinLbl.font = [UIFont systemFontOfSize:16];
    jellyfinLbl.textColor = [theme textColor];
    [jellyfinRow addSubview:jellyfinLbl];
    self.jellyfinEnabledSwitch = [[UISwitch alloc] init];
    self.jellyfinEnabledSwitch.frame = CGRectMake(jellyfinRow.bounds.size.width - 51, 6, 51, 31);
    [jellyfinRow addSubview:self.jellyfinEnabledSwitch];
    [self.contentView addSubview:jellyfinRow];
    yOffset += 50;

    [self addJellyfinFieldLabel:@"Server URL" atY:&yOffset padding:padding];
    self.jellyfinServerURLField = [self makeJellyfinFieldWithPlaceholder:@"http://192.168.1.x:8096" atY:&yOffset padding:padding];
    self.jellyfinServerURLField.keyboardType = UIKeyboardTypeURL;

    [self addJellyfinFieldLabel:@"Username" atY:&yOffset padding:padding];
    self.jellyfinUsernameField = [self makeJellyfinFieldWithPlaceholder:@"Username" atY:&yOffset padding:padding];

    [self addJellyfinFieldLabel:@"Password" atY:&yOffset padding:padding];
    self.jellyfinPasswordField = [self makeJellyfinFieldWithPlaceholder:@"Used only to sign in; not stored" atY:&yOffset padding:padding];
    self.jellyfinPasswordField.secureTextEntry = YES;

    self.jellyfinSignInButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jellyfinSignInButton.frame = CGRectMake(padding, yOffset, fieldWidth, 44);
    [self.jellyfinSignInButton setTitle:@"Sign In" forState:UIControlStateNormal];
    [self.jellyfinSignInButton setTitleColor:[theme accentColor] forState:UIControlStateNormal];
    self.jellyfinSignInButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.jellyfinSignInButton addTarget:self action:@selector(jellyfinSignInTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.jellyfinSignInButton];
    yOffset += 50;

    self.jellyfinTargetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jellyfinTargetButton.frame = CGRectMake(padding, yOffset, fieldWidth, 44);
    [self.jellyfinTargetButton setTitle:@"Pick Target Client" forState:UIControlStateNormal];
    self.jellyfinTargetButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.jellyfinTargetButton setTitleColor:[theme accentColor] forState:UIControlStateNormal];
    [self.jellyfinTargetButton addTarget:self action:@selector(jellyfinPickTargetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.jellyfinTargetButton];
    yOffset += 50;

    self.jellyfinStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, fieldWidth, 40)];
    self.jellyfinStatusLabel.numberOfLines = 0;
    self.jellyfinStatusLabel.font = [UIFont systemFontOfSize:13];
    self.jellyfinStatusLabel.textColor = [theme secondaryTextColor];
    [self.contentView addSubview:self.jellyfinStatusLabel];
    yOffset += 50;
    // --- end Jellyfin section ---

    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.frame = CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 50);
    [self.saveButton setTitle:@"Save & Continue" forState:UIControlStateNormal];
    self.saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.saveButton.backgroundColor = [theme accentColor];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.layer.cornerRadius = 12.0;
    [self.saveButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.saveButton];
    yOffset += 60;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.view.bounds.size.width - 2 * padding, 60)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = [theme secondaryTextColor];
    [self.contentView addSubview:self.statusLabel];
    yOffset += 70;

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tapGesture];

    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, yOffset);
    self.scrollView.contentSize = self.contentView.frame.size;
}

- (void)loadSavedSettings {
    HAAPIClient *client = [HAAPIClient sharedClient];
    if (client.baseURL) {
        self.baseURLField.text = client.baseURL;
    }
    if (client.accessToken) {
        self.accessTokenField.text = client.accessToken;
    }
    self.batteryReportingSwitch.on = client.batteryReportingEnabled;

    JeevesJellyfinClient *jellyfin = [JeevesJellyfinClient sharedClient];
    self.jellyfinEnabledSwitch.on    = jellyfin.enabled;
    self.jellyfinServerURLField.text = jellyfin.serverURL;
    self.jellyfinUsernameField.text  = jellyfin.userName;
    if ([jellyfin isConfigured]) {
        self.jellyfinStatusLabel.text = [NSString stringWithFormat:@"Signed in as %@", jellyfin.userName ?: @"?"];
    }
    if (jellyfin.currentTarget.name.length > 0) {
        [self.jellyfinTargetButton setTitle:[NSString stringWithFormat:@"Target: %@", jellyfin.currentTarget.name] forState:UIControlStateNormal];
    }
}

- (void)testConnectionTapped {
    [self dismissKeyboard];

    NSString *baseURL = [self.baseURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *accessToken = [self.accessTokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (baseURL.length == 0 || accessToken.length == 0) {
        self.statusLabel.text = @"Please enter both URL and access token";
        self.statusLabel.textColor = [UIColor redColor];
        return;
    }

    self.statusLabel.text = @"Testing connection...";
    self.statusLabel.textColor = [UIColor grayColor];
    self.testConnectionButton.enabled = NO;

    HAAPIClient *tempClient = [[HAAPIClient alloc] init];
    [tempClient configureWithBaseURL:baseURL accessToken:accessToken];

    [tempClient fetchStatesWithCompletion:^(NSArray<HAEntity *> *entities, NSError *error) {
        self.testConnectionButton.enabled = YES;

        if (error) {
            self.statusLabel.text = [NSString stringWithFormat:@"Connection failed: %@", error.localizedDescription];
            self.statusLabel.textColor = [UIColor redColor];
        } else {
            self.statusLabel.text = [NSString stringWithFormat:@"Success! Found %lu entities", (unsigned long)entities.count];
            self.statusLabel.textColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.0 alpha:1.0];
        }
    }];
}

- (void)saveTapped {
    [self dismissKeyboard];

    NSString *baseURL = [self.baseURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *accessToken = [self.accessTokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (baseURL.length == 0 || accessToken.length == 0) {
        self.statusLabel.text = @"Please enter both URL and access token";
        self.statusLabel.textColor = [UIColor redColor];
        return;
    }

    [[HAAPIClient sharedClient] configureWithBaseURL:baseURL accessToken:accessToken];

    // Save battery reporting setting
    [HAAPIClient sharedClient].batteryReportingEnabled = self.batteryReportingSwitch.on;

    // Save Jellyfin settings (server URL and credentials are saved by Sign In)
    [JeevesJellyfinClient sharedClient].enabled = self.jellyfinEnabledSwitch.on;
    [[NSNotificationCenter defaultCenter] postNotificationName:JellyfinSettingsChangedNotification object:nil];

    if (self.isInitialSetup) {
        JeevesDashboardViewController *dashboardVC = [[JeevesDashboardViewController alloc] init];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:dashboardVC];
        [[JeevesThemeManager sharedManager] applyThemeToNavigationBar:navController.navigationBar];

        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        window.rootViewController = navController;

        [UIView transitionWithView:window
                          duration:0.3
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:nil
                        completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.baseURLField) {
        [self.accessTokenField becomeFirstResponder];
    } else if (textField == self.accessTokenField) {
        [self dismissKeyboard];
        [self saveTapped];
    }
    return YES;
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;

    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0, 0, keyboardHeight, 0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.scrollView.contentInset = UIEdgeInsetsZero;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

#pragma mark - Jellyfin

- (void)addJellyfinFieldLabel:(NSString *)text atY:(CGFloat *)yOffset padding:(CGFloat)padding {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(padding, *yOffset, self.view.bounds.size.width - 2 * padding, 20)];
    label.text = text;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = [[JeevesThemeManager sharedManager] secondaryTextColor];
    [self.contentView addSubview:label];
    *yOffset += 25;
}

- (UITextField *)makeJellyfinFieldWithPlaceholder:(NSString *)placeholder atY:(CGFloat *)yOffset padding:(CGFloat)padding {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(padding, *yOffset, self.view.bounds.size.width - 2 * padding, 44)];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.delegate = self;
    [self.contentView addSubview:field];
    *yOffset += 56;
    return field;
}

- (void)setJellyfinStatus:(NSString *)text color:(UIColor *)color {
    self.jellyfinStatusLabel.text = text;
    self.jellyfinStatusLabel.textColor = color;
}

- (void)jellyfinSignInTapped {
    [self dismissKeyboard];
    NSString *url      = [self.jellyfinServerURLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *username = [self.jellyfinUsernameField.text  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = self.jellyfinPasswordField.text ?: @"";
    if (url.length == 0 || username.length == 0) {
        [self setJellyfinStatus:@"Enter Jellyfin URL and username" color:[UIColor redColor]];
        return;
    }

    [self setJellyfinStatus:@"Signing in..." color:[UIColor grayColor]];
    JeevesJellyfinClient *client = [JeevesJellyfinClient sharedClient];
    [client signInToServer:url username:username password:password completion:^(BOOL success, NSError *error) {
        self.jellyfinPasswordField.text = nil;
        if (!success) {
            [self setJellyfinStatus:[NSString stringWithFormat:@"Sign in failed: %@", error.localizedDescription ?: @"no response"] color:[UIColor redColor]];
            return;
        }
        [client fetchLibrariesWithCompletion:^(NSArray *libraries, NSError *libErr) {
            NSString *text = libraries
                ? [NSString stringWithFormat:@"Signed in as %@ \u2014 %lu libraries", client.userName, (unsigned long)libraries.count]
                : [NSString stringWithFormat:@"Signed in as %@", client.userName];
            [self setJellyfinStatus:text color:[UIColor colorWithRed:0.0 green:0.7 blue:0.0 alpha:1.0]];
        }];
    }];
}

- (void)jellyfinPickTargetTapped {
    [self dismissKeyboard];
    JeevesJellyfinClient *client = [JeevesJellyfinClient sharedClient];
    if (![client isConfigured]) {
        [self setJellyfinStatus:@"Sign in to Jellyfin first" color:[UIColor redColor]];
        return;
    }

    [self setJellyfinStatus:@"Loading clients..." color:[UIColor grayColor]];
    [client fetchAvailableTargetsWithCompletion:^(NSArray<JeevesJellyfinTarget *> *targets, NSError *error) {
        if (error || targets == nil) {
            [self setJellyfinStatus:[NSString stringWithFormat:@"No clients: %@", error.localizedDescription ?: @"unreachable"] color:[UIColor redColor]];
            return;
        }
        if (targets.count == 0) {
            [self setJellyfinStatus:@"No remote-controllable Jellyfin clients are active" color:[UIColor redColor]];
            return;
        }
        self.jellyfinStatusLabel.text = nil;
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Pick Target Client"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        for (JeevesJellyfinTarget *t in targets) {
            NSString *title = [NSString stringWithFormat:@"%@ (%@)", t.name ?: @"Client", t.client ?: @"?"];
            JeevesJellyfinTarget *captured = t;
            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [client saveTargetToDefaults:captured];
                [self.jellyfinTargetButton setTitle:[NSString stringWithFormat:@"Target: %@", captured.name] forState:UIControlStateNormal];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        if (sheet.popoverPresentationController) {
            sheet.popoverPresentationController.sourceView = self.jellyfinTargetButton;
            sheet.popoverPresentationController.sourceRect = self.jellyfinTargetButton.bounds;
        }
        [self presentViewController:sheet animated:YES completion:nil];
    }];
}

@end
