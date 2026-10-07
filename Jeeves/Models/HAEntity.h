#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, HAEntityType) {
    HAEntityTypeUnknown,
    HAEntityTypeLight,
    HAEntityTypeSwitch,
    HAEntityTypeSensor,
    HAEntityTypeCamera,
    HAEntityTypeBinarySensor,
    HAEntityTypeScript,
    HAEntityTypeInputBoolean,
    HAEntityTypeVacuum,
    HAEntityTypeButton,
    HAEntityTypeFan,
    HAEntityTypeClimate,
    HAEntityTypeNumber,
    HAEntityTypeSelect
};

@interface HAEntity : NSObject

@property (nonatomic, strong) NSString *entityId;
@property (nonatomic, strong) NSString *friendlyName;
@property (nonatomic, strong) NSString *state;
@property (nonatomic, strong) NSDictionary *attributes;
@property (nonatomic, assign) HAEntityType entityType;
@property (nonatomic, strong) NSString *areaName; // Home Assistant area/room name
@property (nonatomic, strong) NSDate *lastChanged;  // When the state last changed (nil if unknown)

+ (instancetype)entityFromDictionary:(NSDictionary *)dict;
- (BOOL)isOn;
- (NSString *)icon;
- (UIColor *)stateColor;
- (BOOL)supportsBrightness;
- (NSInteger)brightness; // 0-100 percentage

// Light capabilities (from supported_color_modes / supported_features / effect_list)
- (BOOL)supportsColor;
- (BOOL)supportsColorTemperature;
- (NSArray<NSString *> *)effectList;     // empty if effects aren't supported
- (NSString *)currentEffect;             // nil if none
- (BOOL)hasHSColor;                      // YES if hs_color is reported
- (CGFloat)hue;                          // 0-360, from hs_color
- (CGFloat)saturation;                   // 0-100, from hs_color
- (NSInteger)minColorTemperatureKelvin;  // warmest
- (NSInteger)maxColorTemperatureKelvin;  // coolest
- (NSInteger)colorTemperatureKelvin;     // 0 if unknown
- (BOOL)usesKelvinColorTemperature;      // NO for older HA versions that only report mireds

@end
