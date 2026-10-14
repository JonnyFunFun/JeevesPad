#import "JeevesFleetSettings.h"
#import "HAAPIClient.h"
#import "JeevesRoom.h"
#import "JeevesCardSettings.h"
#import "JeevesWeatherSettings.h"
#import "JeevesIdleManager.h"
#import "JeevesJellyfinClient.h"

NSString * const JeevesFleetSettingsAppliedNotification = @"JeevesFleetSettingsAppliedNotification";
NSString * const JeevesFleetConfigurationDidChangeNotification = @"JeevesFleetConfigurationDidChangeNotification";

static NSString * const kDefaultsFleetEnabled = @"JeevesFleetEnabled";
static NSString * const kDefaultsFleetCode    = @"JeevesFleetCode";
static NSString * const kSnapshotKeys   = @"keys";   // keys the sender knows about
static NSString * const kSnapshotValues = @"values"; // values of those it has set

@implementation JeevesFleetSettings

+ (instancetype)sharedSettings {
    static JeevesFleetSettings *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _enabled = [d boolForKey:kDefaultsFleetEnabled];
        _fleetCode = [d stringForKey:kDefaultsFleetCode];
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDefaultsFleetEnabled];
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesFleetConfigurationDidChangeNotification object:self];
}

- (void)setFleetCode:(NSString *)fleetCode {
    NSString *trimmed = [fleetCode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _fleetCode = trimmed.length > 0 ? trimmed : nil;
    if (_fleetCode) [[NSUserDefaults standardUserDefaults] setObject:_fleetCode forKey:kDefaultsFleetCode];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsFleetCode];
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesFleetConfigurationDidChangeNotification object:self];
}

+ (NSArray<NSString *> *)sharedKeys {
    return @[
        // Home Assistant connection
        @"HABaseURL", @"HAAccessToken", @"HABatteryReportingEnabled",
        // Dashboards: rooms, Home cards, card names/sizes
        @"JeevesRooms", @"HomeSensorIds", @"JeevesCardSettings",
        // Home weather column
        @"JeevesWeatherSource", @"JeevesWeatherEntityId", @"JeevesWeatherTemperatureEntityId", @"JeevesWeatherReadingEntityIds",
        // Idle behaviour (wake-on-motion is per-device: it needs camera permission on each iPad)
        @"JeevesIdleHomeTimeout", @"JeevesIdleDimsWhenIdle",
        // Jellyfin server (sign-in tokens are tied to each device, so each iPad signs in itself)
        @"JellyfinEnabled", @"JellyfinServerURL",
    ];
}

- (NSDictionary *)snapshot {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in [[self class] sharedKeys]) {
        id value = [d objectForKey:key];
        if (value) values[key] = value;
    }
    return @{kSnapshotKeys: [[self class] sharedKeys], kSnapshotValues: values};
}

- (BOOL)applySnapshot:(NSDictionary *)snapshot fromDevice:(NSString *)deviceName {
    NSArray *senderKeys = snapshot[kSnapshotKeys];
    NSDictionary *values = snapshot[kSnapshotValues];
    if (![senderKeys isKindOfClass:[NSArray class]] || ![values isKindOfClass:[NSDictionary class]]) return NO;

    // Only touch keys both sides share: a sender running an older version mustn't
    // erase settings it doesn't know about, and unknown keys are ignored
    NSArray *ourKeys = [[self class] sharedKeys];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in senderKeys) {
        if (![key isKindOfClass:[NSString class]] || ![ourKeys containsObject:key]) continue;
        id value = values[key];
        if (value) [d setObject:value forKey:key];
        else [d removeObjectForKey:key];
    }
    [d synchronize];

    // Everything that caches these settings reloads them
    [[HAAPIClient sharedClient] reloadFromDefaults];
    [[JeevesRoomManager sharedManager] reloadFromDefaults];
    [[JeevesCardSettings sharedSettings] reloadFromDefaults];
    [[JeevesWeatherSettings sharedSettings] reloadFromDefaults];
    [[JeevesIdleManager sharedManager] reloadFromDefaults];
    [[JeevesJellyfinClient sharedClient] reloadFromDefaults];

    NSLog(@"[Fleet] Applied settings from %@", deviceName);
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesFleetSettingsAppliedNotification object:deviceName];
    return YES;
}

@end
