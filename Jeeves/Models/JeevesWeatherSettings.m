#import "JeevesWeatherSettings.h"
#import "HAEntity.h"

NSString * const JeevesWeatherSettingsDidChangeNotification = @"JeevesWeatherSettingsDidChangeNotification";

static NSString * const kDefaultsWeatherSource      = @"JeevesWeatherSource";
static NSString * const kDefaultsWeatherEntity      = @"JeevesWeatherEntityId";
static NSString * const kDefaultsTemperatureEntity  = @"JeevesWeatherTemperatureEntityId";
static NSString * const kDefaultsReadingEntities    = @"JeevesWeatherReadingEntityIds";

@implementation JeevesWeatherSettings

+ (instancetype)sharedSettings {
    static JeevesWeatherSettings *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reloadFromDefaults];
    }
    return self;
}

- (void)reloadFromDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _weatherSource = [d integerForKey:kDefaultsWeatherSource]; // 0 (Automatic) if never set
    _weatherEntityId = [d stringForKey:kDefaultsWeatherEntity];
    _temperatureEntityId = [d stringForKey:kDefaultsTemperatureEntity];
    _readingEntityIds = [d stringArrayForKey:kDefaultsReadingEntities] ?: @[];
}

- (void)saveAndNotify {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:self.weatherSource forKey:kDefaultsWeatherSource];
    if (self.weatherEntityId) [d setObject:self.weatherEntityId forKey:kDefaultsWeatherEntity];
    else [d removeObjectForKey:kDefaultsWeatherEntity];
    if (self.temperatureEntityId) [d setObject:self.temperatureEntityId forKey:kDefaultsTemperatureEntity];
    else [d removeObjectForKey:kDefaultsTemperatureEntity];
    [d setObject:self.readingEntityIds forKey:kDefaultsReadingEntities];
    [d synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesWeatherSettingsDidChangeNotification object:self];
}

- (void)setWeatherSource:(JeevesWeatherSource)weatherSource {
    _weatherSource = weatherSource;
    [self saveAndNotify];
}

- (void)setWeatherEntityId:(NSString *)weatherEntityId {
    _weatherEntityId = [weatherEntityId copy];
    [self saveAndNotify];
}

- (void)setTemperatureEntityId:(NSString *)temperatureEntityId {
    _temperatureEntityId = [temperatureEntityId copy];
    [self saveAndNotify];
}

- (void)setReadingEntityIds:(NSArray<NSString *> *)readingEntityIds {
    _readingEntityIds = [readingEntityIds copy] ?: @[];
    [self saveAndNotify];
}

- (HAEntity *)weatherEntityFromEntities:(NSArray<HAEntity *> *)entities {
    switch (self.weatherSource) {
        case JeevesWeatherSourceNone:
            return nil;
        case JeevesWeatherSourceEntity:
            for (HAEntity *entity in entities) {
                if ([entity.entityId isEqualToString:self.weatherEntityId]) return entity;
            }
            return nil;
        case JeevesWeatherSourceAutomatic:
            for (HAEntity *entity in entities) {
                if ([entity.entityId hasPrefix:@"weather."]) return entity;
            }
            return nil;
    }
    return nil;
}

@end
