#import "JeevesFleetSettings.h"
#import "HAAPIClient.h"
#import "JeevesRoom.h"
#import "JeevesCardSettings.h"
#import "JeevesWeatherSettings.h"
#import "JeevesIdleManager.h"
#import "JeevesJellyfinClient.h"

NSString * const JeevesFleetSettingsAppliedNotification = @"JeevesFleetSettingsAppliedNotification";
NSString * const JeevesFleetConfigurationDidChangeNotification = @"JeevesFleetConfigurationDidChangeNotification";

const NSUInteger JeevesFleetMinimumCodeLength = 8;

static NSString * const kDefaultsFleetEnabled = @"JeevesFleetEnabled";
static NSString * const kDefaultsFleetCode    = @"JeevesFleetCode";
static NSString * const kSnapshotKeys   = @"keys";   // keys the sender knows about
static NSString * const kSnapshotValues = @"values"; // values of those it has set
static NSString * const kSnapshotRooms  = @"rooms";  // JeevesRooms as plain dictionaries
static NSString * const kProvisioningPath = @"Library/Jeeves/provision.plist"; // in the home directory

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

- (BOOL)hasUsableCode {
    return self.fleetCode.length >= JeevesFleetMinimumCodeLength;
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
        // Code that ends Guided Access in Jeeves (whether it's on is per-device)
        @"JeevesGuidedAccessCode",
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
    NSMutableArray *rooms = [NSMutableArray array];
    for (JeevesRoom *room in [JeevesRoomManager sharedManager].rooms) {
        [rooms addObject:@{@"roomId": room.roomId ?: @"",
                           @"name": room.name ?: @"",
                           @"iconType": @(room.iconType),
                           @"entityIds": [room.entityIds copy] ?: @[],
                           @"sortOrder": @(room.sortOrder)}];
    }
    return @{kSnapshotKeys: [[self class] sharedKeys], kSnapshotValues: values, kSnapshotRooms: rooms};
}

// Keyed archive of JeevesRooms from portable room dictionaries, or nil if invalid
+ (NSData *)archivedRoomsFromPortableRooms:(NSArray *)portable {
    NSMutableArray<JeevesRoom *> *rooms = [NSMutableArray array];
    for (NSDictionary *dict in portable) {
        if (![dict isKindOfClass:[NSDictionary class]] || ![dict[@"name"] isKindOfClass:[NSString class]]) return nil;
        JeevesRoom *room = [JeevesRoom roomWithName:dict[@"name"] iconType:[dict[@"iconType"] integerValue]];
        if ([dict[@"roomId"] isKindOfClass:[NSString class]] && [dict[@"roomId"] length] > 0) room.roomId = dict[@"roomId"];
        for (id entityId in ([dict[@"entityIds"] isKindOfClass:[NSArray class]] ? dict[@"entityIds"] : @[])) {
            if ([entityId isKindOfClass:[NSString class]]) [room addEntityId:entityId];
        }
        room.sortOrder = [dict[@"sortOrder"] isKindOfClass:[NSNumber class]] ? [dict[@"sortOrder"] integerValue] : rooms.count;
        [rooms addObject:room];
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [NSKeyedArchiver archivedDataWithRootObject:rooms];
    #pragma clang diagnostic pop
}

- (BOOL)applySnapshot:(NSDictionary *)snapshot fromDevice:(NSString *)deviceName {
    NSArray *senderKeys = snapshot[kSnapshotKeys];
    NSDictionary *values = snapshot[kSnapshotValues];
    if (![senderKeys isKindOfClass:[NSArray class]] || ![values isKindOfClass:[NSDictionary class]]) return NO;

    // Portable rooms (from JeevesPad Manager, or a newer iPad) replace the archived ones
    if ([snapshot[kSnapshotRooms] isKindOfClass:[NSArray class]]) {
        NSData *archived = [[self class] archivedRoomsFromPortableRooms:snapshot[kSnapshotRooms]];
        if (!archived) return NO;
        NSMutableDictionary *merged = [values mutableCopy];
        merged[@"JeevesRooms"] = archived;
        values = merged;
        if (![senderKeys containsObject:@"JeevesRooms"]) senderKeys = [senderKeys arrayByAddingObject:@"JeevesRooms"];
    }

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

- (void)applyProvisioningFileIfPresent {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:kProvisioningPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    // Delete first: it contains the Home Assistant token, and a bad file mustn't be retried forever
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSDictionary *provision = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
    if (![provision isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[Fleet] Ignoring invalid provisioning file");
        return;
    }
    if ([provision[@"fleetCode"] isKindOfClass:[NSString class]]) self.fleetCode = provision[@"fleetCode"];
    if ([provision[@"fleetEnabled"] isKindOfClass:[NSNumber class]]) self.enabled = [provision[@"fleetEnabled"] boolValue];
    NSString *from = [provision[@"from"] isKindOfClass:[NSString class]] ? provision[@"from"] : @"JeevesPad Manager";
    if ([provision[@"settings"] isKindOfClass:[NSDictionary class]]) {
        [self applySnapshot:provision[@"settings"] fromDevice:from];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[Fleet] Applied provisioning from %@", from);
}

@end
