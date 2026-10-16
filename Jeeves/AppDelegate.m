#import "AppDelegate.h"
#import "JeevesDashboardViewController.h"
#import "SettingsViewController.h"
#import "JeevesThemeManager.h"
#import "API/JeevesBatteryReporter.h"
#import "API/JeevesJellyfinClient.h"
#import "JeevesIdleManager.h"
#import "JeevesFleetService.h"
#import "JeevesFleetSettings.h"
#import "JeevesGuidedAccess.h"
#import "JeevesMaintenance.h"

@interface AppDelegate ()

@end

// Crash reports on iOS 9 omit the exception message, and devices often have no syslog
// file, so record uncaught exceptions ourselves: ~/Library/Logs/Jeeves-exception.log
// (/var/mobile/Library/Logs on a jailbroken device).
static void JeevesUncaughtExceptionHandler(NSException *exception) {
    NSString *report = [NSString stringWithFormat:@"%@\n%@: %@\n\n%@\n",
                        [NSDate date], exception.name, exception.reason,
                        [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    NSLog(@"[Jeeves] Uncaught exception: %@", report);

    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *logsDir = [library stringByAppendingPathComponent:@"Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
    [report writeToFile:[logsDir stringByAppendingPathComponent:@"Jeeves-exception.log"]
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:nil];
}

// Preferences domain of the app before it was renamed from HomeButler to Jeeves
static NSString * const kLegacyPreferencesDomain = @"com.homebutler.HomeButler";

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSSetUncaughtExceptionHandler(&JeevesUncaughtExceptionHandler);

    // Must run before anything reads NSUserDefaults
    [self migrateLegacySettings];
    // Settings left by the JeevesPad Manager app when it installed or enrolled this iPad
    [[JeevesFleetSettings sharedSettings] applyProvisioningFileIfPresent];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    self.window.rootViewController = [self makeRootViewController];
    [self.window makeKeyAndVisible];

    // Start battery reporting (will only POST if webhook URL is configured)
    [[JeevesBatteryReporter sharedReporter] startReporting];

    // Idle timeout: return to Home, then dim the screen
    JeevesIdleManager *idle = [JeevesIdleManager sharedManager];
    __weak typeof(self) weakSelf = self;
    idle.returnHomeHandler = ^{
        [weakSelf returnToHome];
    };
    [idle start];

    // Guided Access requested from Home Assistant (or this iPad) comes back after a restart
    [[JeevesGuidedAccess sharedManager] start];

    // Maintenance mode turned on from Home Assistant stays on across restarts
    [[JeevesMaintenance sharedManager] start];

    // Fleet: advertise this iPad (Bonjour) and accept settings from other iPads
    [[JeevesFleetService sharedService] start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fleetSettingsApplied:)
                                                 name:JeevesFleetSettingsAppliedNotification object:nil];

    // Warm-init the Jellyfin client (creates its persistent device ID on first launch)
    (void)[JeevesJellyfinClient sharedClient];

    return YES;
}

// Copies settings saved by HomeButler into Jeeves' defaults (unless Jeeves is already
// configured), then deletes the old preferences.
- (void)migrateLegacySettings {
    CFStringRef legacyDomain = (__bridge CFStringRef)kLegacyPreferencesDomain;
    NSArray *legacyKeys = CFBridgingRelease(CFPreferencesCopyKeyList(legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (legacyKeys.count == 0) return;

    NSDictionary *legacyValues = CFBridgingRelease(CFPreferencesCopyMultiple((__bridge CFArrayRef)legacyKeys, legacyDomain,
                                                                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults stringForKey:@"HABaseURL"].length == 0) {
        NSDictionary *renamedKeys = @{@"HBRooms": @"JeevesRooms"};
        for (NSString *key in legacyValues) {
            [defaults setObject:legacyValues[key] forKey:renamedKeys[key] ?: key];
        }
        if (![defaults synchronize]) {
            NSLog(@"[AppDelegate] Failed to save migrated settings; keeping legacy preferences");
            return;
        }
        NSLog(@"[AppDelegate] Migrated %lu settings from %@", (unsigned long)legacyValues.count, kLegacyPreferencesDomain);
    }

    CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)legacyKeys, legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// The dashboard once Home Assistant is configured, otherwise first-run setup
- (UIViewController *)makeRootViewController {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *baseURL = [defaults stringForKey:@"HABaseURL"];
    NSString *accessToken = [defaults stringForKey:@"HAAccessToken"];

    UIViewController *root;
    if (baseURL.length > 0 && accessToken.length > 0) {
        root = [[JeevesDashboardViewController alloc] init];
    } else {
        SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
        settingsVC.isInitialSetup = YES;
        root = settingsVC;
    }
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:root];
    [[JeevesThemeManager sharedManager] applyThemeToNavigationBar:navController.navigationBar];
    return navController;
}

// Another iPad's settings were applied: rebuild the UI so every screen picks them up
- (void)fleetSettingsApplied:(NSNotification *)note {
    NSString *source = [note.object isKindOfClass:[NSString class]] ? note.object : @"another iPad";
    [self rebuildInterfaceWithNoticeTitle:@"Settings Updated"
                                  message:[NSString stringWithFormat:@"Settings were copied from %@.", source]];
}

// Replaces the whole UI (so every screen re-reads its settings), optionally showing
// a brief notice that closes itself (nobody may be at the wall panel to dismiss it)
- (void)rebuildInterfaceWithNoticeTitle:(NSString *)title message:(NSString *)message {
    UINavigationController *oldNav = (UINavigationController *)self.window.rootViewController;
    void (^replace)(void) = ^{
        if ([oldNav isKindOfClass:[UINavigationController class]]) {
            id oldRoot = oldNav.viewControllers.firstObject;
            if ([oldRoot isKindOfClass:[JeevesDashboardViewController class]]) [oldRoot stopUpdates];
        }
        self.window.rootViewController = [self makeRootViewController];
        if (title) [self showNoticeWithTitle:title message:message duration:3];
    };
    if (oldNav.presentedViewController) {
        [oldNav dismissViewControllerAnimated:NO completion:replace];
    } else {
        replace();
    }
}

- (void)showNoticeWithTitle:(NSString *)title message:(NSString *)message duration:(NSTimeInterval)duration {
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if ([presenter isKindOfClass:[UIAlertController class]]) return; // don't stack notices

    UIAlertController *notice = [UIAlertController alertControllerWithTitle:title message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [presenter presentViewController:notice animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (notice.presentingViewController) [notice dismissViewControllerAnimated:YES completion:nil];
    });
}

- (NSString *)performRemoteCommand:(NSString *)command value:(id)value {
    JeevesIdleManager *idle = [JeevesIdleManager sharedManager];
    if ([command isEqualToString:@"home"]) {
        [idle userDidInteract];
        [self returnToHome];
    } else if ([command isEqualToString:@"reload"]) {
        [self rebuildInterfaceWithNoticeTitle:nil message:nil];
    } else if ([command isEqualToString:@"wake"]) {
        [idle userDidInteract];
    } else if ([command isEqualToString:@"identify"]) {
        [idle userDidInteract];
        [self showNoticeWithTitle:[UIDevice currentDevice].name message:@"Identified from Home Assistant" duration:5];
    } else if ([command isEqualToString:@"guided_access"]) {
        if (![value isKindOfClass:[NSNumber class]]) return @"guided_access needs true or false";
        // The outcome arrives asynchronously; the status request reports it
        [[JeevesGuidedAccess sharedManager] setWanted:[value boolValue] completion:nil];
    } else if ([command isEqualToString:@"maintenance"]) {
        // value: {on: bool, message: optional text for the notice}
        NSDictionary *options = [value isKindOfClass:[NSDictionary class]] ? value : nil;
        if (![options[@"on"] isKindOfClass:[NSNumber class]]) return @"maintenance needs {on: true/false}";
        NSString *message = [options[@"message"] isKindOfClass:[NSString class]] ? options[@"message"] : nil;
        [[JeevesMaintenance sharedManager] setActive:[options[@"on"] boolValue] message:message];
    } else if ([command isEqualToString:@"brightness"]) {
        if (![value isKindOfClass:[NSNumber class]]) return @"brightness needs a value from 0 to 1";
        [idle userDidInteract]; // undims first, so the dimmer doesn't restore its own level afterwards
        [UIScreen mainScreen].brightness = MAX(0.0, MIN(1.0, [value doubleValue]));
    } else {
        return [NSString stringWithFormat:@"Unknown command \u201c%@\u201d", command];
    }
    return nil;
}

// Closes any open screens and shows the Home dashboard. Does nothing during
// first-run setup (when the dashboard isn't the root yet).
- (void)returnToHome {
    UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
    if (![nav isKindOfClass:[UINavigationController class]]) return;
    JeevesDashboardViewController *dashboard = (JeevesDashboardViewController *)nav.viewControllers.firstObject;
    if (![dashboard isKindOfClass:[JeevesDashboardViewController class]]) return;

    void (^showHome)(void) = ^{
        [nav popToRootViewControllerAnimated:NO];
        [dashboard showHome];
    };
    if (nav.presentedViewController) {
        [nav dismissViewControllerAnimated:YES completion:showHome];
    } else {
        showHome();
    }
}

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
}

- (void)applicationWillTerminate:(UIApplication *)application {
}

@end
