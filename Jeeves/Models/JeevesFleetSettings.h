#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted after settings from another iPad are applied (object: that iPad's name)
extern NSString * const JeevesFleetSettingsAppliedNotification;
// Posted when fleet sync is enabled/disabled or the fleet code changes
extern NSString * const JeevesFleetConfigurationDidChangeNotification;

// Which settings are shared across a fleet of iPads, and this iPad's fleet
// configuration. Device-specific settings (battery webhook ID, Jellyfin sign-in
// and playback target, wake-on-motion, screen state) are never shared.
@interface JeevesFleetSettings : NSObject

+ (instancetype)sharedSettings;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *fleetCode; // must match on every iPad in the fleet

// Shortest fleet code accepted: it encrypts settings that include the Home Assistant token,
// and a captured request could be used to guess a short code offline
extern const NSUInteger JeevesFleetMinimumCodeLength;

// A fleet code is set and long enough to use
@property (nonatomic, readonly) BOOL hasUsableCode;

+ (NSArray<NSString *> *)sharedKeys;

// Shared settings as a property-list dictionary: {keys, values, rooms}. `rooms` repeats
// JeevesRooms (a keyed archive) as plain dictionaries {roomId, name, iconType,
// entityIds, sortOrder}, so tools that can't read keyed archives can edit rooms.
- (NSDictionary *)snapshot;
// Replaces the settings listed in the snapshot's `keys` (removing listed keys that have
// no value) and reloads everything that caches them. A `rooms` array replaces JeevesRooms.
- (BOOL)applySnapshot:(NSDictionary *)snapshot fromDevice:(NSString *)deviceName;

// Applies (then deletes) ~/Library/Jeeves/provision.plist, which the JeevesPad Manager
// app writes over SSH when it installs or enrolls this iPad: {fleetEnabled, fleetCode,
// settings (a snapshot), from}. Call at launch, before the UI reads any settings.
- (void)applyProvisioningFileIfPresent;

@end

NS_ASSUME_NONNULL_END
