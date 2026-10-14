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

+ (NSArray<NSString *> *)sharedKeys;

// Shared settings as a property-list dictionary
- (NSDictionary *)snapshot;
// Replaces this iPad's shared settings and reloads everything that caches them
- (BOOL)applySnapshot:(NSDictionary *)snapshot fromDevice:(NSString *)deviceName;

@end

NS_ASSUME_NONNULL_END
