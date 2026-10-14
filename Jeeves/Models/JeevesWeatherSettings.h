#import <Foundation/Foundation.h>

@class HAEntity;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JeevesWeatherSource) {
    JeevesWeatherSourceAutomatic = 0, // first weather.* entity in Home Assistant
    JeevesWeatherSourceNone,          // no weather entity: no condition or forecast
    JeevesWeatherSourceEntity         // a specific weather.* entity
};

// Posted when any weather setting changes
extern NSString * const JeevesWeatherSettingsDidChangeNotification;

// What the Home screen's weather column shows. A weather entity supplies the
// condition, icon and forecast; sensors (e.g. from a personal weather station)
// can supply the temperature and any number of extra readings.
@interface JeevesWeatherSettings : NSObject

+ (instancetype)sharedSettings;

@property (nonatomic, assign) JeevesWeatherSource weatherSource;
@property (nonatomic, copy, nullable) NSString *weatherEntityId;        // for JeevesWeatherSourceEntity
@property (nonatomic, copy, nullable) NSString *temperatureEntityId;    // nil: the weather entity's temperature
@property (nonatomic, copy) NSArray<NSString *> *readingEntityIds;      // extra readings, in display order

// The weather entity to use given the current states, or nil
- (nullable HAEntity *)weatherEntityFromEntities:(NSArray<HAEntity *> *)entities;

// Re-reads settings from NSUserDefaults (e.g. after another iPad shared its settings)
- (void)reloadFromDefaults;

@end

NS_ASSUME_NONNULL_END
