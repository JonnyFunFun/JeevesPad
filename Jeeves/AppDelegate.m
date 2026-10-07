#import "AppDelegate.h"
#import "JeevesDashboardViewController.h"
#import "SettingsViewController.h"
#import "JeevesThemeManager.h"
#import "API/JeevesBatteryReporter.h"
#import "API/JeevesJellyfinClient.h"

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

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *baseURL = [defaults stringForKey:@"HABaseURL"];
    NSString *accessToken = [defaults stringForKey:@"HAAccessToken"];

    UIViewController *rootViewController;

    if (baseURL && accessToken && baseURL.length > 0 && accessToken.length > 0) {
        JeevesDashboardViewController *dashboardVC = [[JeevesDashboardViewController alloc] init];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:dashboardVC];
        [[JeevesThemeManager sharedManager] applyThemeToNavigationBar:navController.navigationBar];
        rootViewController = navController;
    } else {
        SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
        settingsVC.isInitialSetup = YES;
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        [[JeevesThemeManager sharedManager] applyThemeToNavigationBar:navController.navigationBar];
        rootViewController = navController;
    }

    self.window.rootViewController = rootViewController;
    [self.window makeKeyAndVisible];

    // Start battery reporting (will only POST if webhook URL is configured)
    [[JeevesBatteryReporter sharedReporter] startReporting];

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
