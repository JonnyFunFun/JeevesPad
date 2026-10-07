#import "HAEntity.h"

@implementation HAEntity

+ (instancetype)entityFromDictionary:(NSDictionary *)dict {
    HAEntity *entity = [[HAEntity alloc] init];
    entity.entityId = dict[@"entity_id"];
    entity.state = dict[@"state"];
    entity.attributes = dict[@"attributes"];
    entity.friendlyName = entity.attributes[@"friendly_name"] ?: entity.entityId;
    entity.entityType = [self typeFromEntityId:entity.entityId];
    entity.lastChanged = [self dateFromHATimestamp:dict[@"last_changed"]];

    // Try to extract area/room name from various HA attributes
    // Check for common attribute names that contain area info
    NSDictionary *attrs = entity.attributes;
    if (attrs) {
        // Try various attribute names that Home Assistant might use for area
        NSString *area = attrs[@"area_name"];
        if (!area) area = attrs[@"room"];
        if (!area) area = attrs[@"location"];
        if (!area) {
            // Check if friendly_name contains a room prefix (e.g., "Living Room Light" -> "Living Room")
            NSString *friendlyName = attrs[@"friendly_name"];
            if (friendlyName && friendlyName.length > 0) {
                // Look for common room name patterns at the start
                NSArray *commonRooms = @[@"Kitchen", @"Living Room", @"Bedroom", @"Bathroom", @"Office",
                                         @"Dining Room", @"Garage", @"Basement", @"Attic", @"Porch",
                                         @"Patio", @"Hallway", @"Closet", @"Laundry", @"Nursery",
                                         @"Guest Room", @"Master Bedroom", @"Kids Room", @"Study"];
                for (NSString *roomName in commonRooms) {
                    if ([friendlyName hasPrefix:roomName] && friendlyName.length > roomName.length) {
                        area = roomName;
                        break;
                    }
                }
            }
        }
        entity.areaName = area;
    }

    return entity;
}

// HA timestamps look like 2024-01-01T12:34:56.123456+00:00 (fractional part optional)
+ (NSDate *)dateFromHATimestamp:(id)value {
    if (![value isKindOfClass:[NSString class]]) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });
    NSString *s = value;
    // Strip fractional seconds; NSDateFormatter on iOS 9 handles >3 digits inconsistently
    NSRange dot = [s rangeOfString:@"."];
    if (dot.location != NSNotFound) {
        NSRange tz = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"+-Z"]
                                        options:0
                                          range:NSMakeRange(dot.location, s.length - dot.location)];
        s = [[s substringToIndex:dot.location] stringByAppendingString:(tz.location != NSNotFound ? [s substringFromIndex:tz.location] : @"")];
    }
    @synchronized (formatter) {
        return [formatter dateFromString:s];
    }
}

+ (HAEntityType)typeFromEntityId:(NSString *)entityId {
    if ([entityId hasPrefix:@"light."]) {
        return HAEntityTypeLight;
    } else if ([entityId hasPrefix:@"switch."]) {
        return HAEntityTypeSwitch;
    } else if ([entityId hasPrefix:@"sensor."]) {
        return HAEntityTypeSensor;
    } else if ([entityId hasPrefix:@"camera."]) {
        return HAEntityTypeCamera;
    } else if ([entityId hasPrefix:@"binary_sensor."]) {
        return HAEntityTypeBinarySensor;
    } else if ([entityId hasPrefix:@"script."]) {
        return HAEntityTypeScript;
    } else if ([entityId hasPrefix:@"input_boolean."]) {
        return HAEntityTypeInputBoolean;
    } else if ([entityId hasPrefix:@"vacuum."]) {
        return HAEntityTypeVacuum;
    } else if ([entityId hasPrefix:@"button."]) {
        return HAEntityTypeButton;
    } else if ([entityId hasPrefix:@"fan."]) {
        return HAEntityTypeFan;
    } else if ([entityId hasPrefix:@"climate."]) {
        return HAEntityTypeClimate;
    } else if ([entityId hasPrefix:@"number."]) {
        return HAEntityTypeNumber;
    } else if ([entityId hasPrefix:@"select."]) {
        return HAEntityTypeSelect;
    }
    return HAEntityTypeUnknown;
}

- (BOOL)isOn {
    if (!self.state || ![self.state isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [self.state isEqualToString:@"on"];
}

- (NSString *)icon {
    switch (self.entityType) {
        case HAEntityTypeLight:
            return self.isOn ? @"💡" : @"⚪️";
        case HAEntityTypeSwitch:
            return self.isOn ? @"🔌" : @"⚫️";
        case HAEntityTypeSensor:
            return @"📊";
        case HAEntityTypeCamera:
            return @"📷";
        case HAEntityTypeBinarySensor:
            return self.isOn ? @"✓" : @"✗";
        case HAEntityTypeScript:
            return @"▶️";
        case HAEntityTypeInputBoolean:
            return self.isOn ? @"✓" : @"○";
        case HAEntityTypeVacuum:
            return @"🧹";
        case HAEntityTypeButton:
            return @"⏺";
        case HAEntityTypeFan:
            return self.isOn ? @"🌀" : @"○";
        case HAEntityTypeClimate:
            return @"🌡";
        case HAEntityTypeNumber:
            return @"#";
        case HAEntityTypeSelect:
            return @"☰";
        default:
            return @"❓";
    }
}

- (UIColor *)stateColor {
    if (self.isOn) {
        return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    } else {
        return [UIColor grayColor];
    }
}

- (BOOL)supportsBrightness {
    // Check if entity has brightness attribute or supported_features includes brightness
    if (self.entityType != HAEntityTypeLight) {
        return NO;
    }

    // Defensive check for attributes
    if (!self.attributes || ![self.attributes isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    // Check for brightness in attributes (indicates it supports it)
    id brightnessValue = self.attributes[@"brightness"];
    if (brightnessValue && ![brightnessValue isKindOfClass:[NSNull class]]) {
        return YES;
    }

    // Check supported_features bitmask (bit 0 = brightness)
    id supportedFeatures = self.attributes[@"supported_features"];
    if (supportedFeatures && [supportedFeatures isKindOfClass:[NSNumber class]]) {
        if ([supportedFeatures integerValue] & 1) {
            return YES;
        }
    }

    // Also check supported_color_modes
    id colorModesValue = self.attributes[@"supported_color_modes"];
    if (colorModesValue && [colorModesValue isKindOfClass:[NSArray class]]) {
        NSArray *colorModes = (NSArray *)colorModesValue;
        for (id modeObj in colorModes) {
            if ([modeObj isKindOfClass:[NSString class]]) {
                NSString *mode = (NSString *)modeObj;
                if ([mode isEqualToString:@"brightness"] ||
                    [mode isEqualToString:@"color_temp"] ||
                    [mode isEqualToString:@"hs"] ||
                    [mode isEqualToString:@"rgb"] ||
                    [mode isEqualToString:@"rgbw"] ||
                    [mode isEqualToString:@"xy"]) {
                    return YES;
                }
            }
        }
    }

    return NO;
}

#pragma mark - Light capabilities

// Legacy supported_features bits (pre color-mode lights)
static const NSInteger kLightFeatureColorTemp = 2;
static const NSInteger kLightFeatureEffect    = 4;
static const NSInteger kLightFeatureColor     = 16;

- (id)attribute:(NSString *)key ofClass:(Class)cls {
    if (![self.attributes isKindOfClass:[NSDictionary class]]) return nil;
    id value = self.attributes[key];
    return [value isKindOfClass:cls] ? value : nil;
}

- (NSArray<NSString *> *)supportedColorModes {
    return [self attribute:@"supported_color_modes" ofClass:[NSArray class]] ?: @[];
}

- (NSInteger)legacySupportedFeatures {
    return [[self attribute:@"supported_features" ofClass:[NSNumber class]] integerValue];
}

- (BOOL)supportsColor {
    if (self.entityType != HAEntityTypeLight) return NO;
    NSArray *modes = [self supportedColorModes];
    if (modes.count > 0) {
        for (NSString *mode in @[@"hs", @"xy", @"rgb", @"rgbw", @"rgbww"]) {
            if ([modes containsObject:mode]) return YES;
        }
        return NO;
    }
    return ([self legacySupportedFeatures] & kLightFeatureColor) != 0;
}

- (BOOL)supportsColorTemperature {
    if (self.entityType != HAEntityTypeLight) return NO;
    NSArray *modes = [self supportedColorModes];
    if (modes.count > 0) return [modes containsObject:@"color_temp"];
    return ([self legacySupportedFeatures] & kLightFeatureColorTemp) != 0;
}

- (NSArray<NSString *> *)effectList {
    if (self.entityType != HAEntityTypeLight) return @[];
    NSArray *list = [self attribute:@"effect_list" ofClass:[NSArray class]];
    if (list.count == 0) return @[];
    // effect_list is authoritative when present; the feature bit only confirms it
    NSInteger features = [self legacySupportedFeatures];
    if (features != 0 && !(features & kLightFeatureEffect)) return @[];
    NSMutableArray *names = [NSMutableArray array];
    for (id e in list) if ([e isKindOfClass:[NSString class]]) [names addObject:e];
    return names;
}

- (NSString *)currentEffect {
    NSString *effect = [self attribute:@"effect" ofClass:[NSString class]];
    return ([effect isEqualToString:@"None"] || [effect isEqualToString:@"none"]) ? nil : effect;
}

- (BOOL)hasHSColor {
    return [[self attribute:@"hs_color" ofClass:[NSArray class]] count] >= 2;
}

- (CGFloat)hue {
    NSArray *hs = [self attribute:@"hs_color" ofClass:[NSArray class]];
    return hs.count >= 2 ? [hs[0] doubleValue] : 0;
}

- (CGFloat)saturation {
    NSArray *hs = [self attribute:@"hs_color" ofClass:[NSArray class]];
    return hs.count >= 2 ? [hs[1] doubleValue] : 0;
}

- (BOOL)usesKelvinColorTemperature {
    return [self attribute:@"min_color_temp_kelvin" ofClass:[NSNumber class]] != nil;
}

// Mireds and kelvin are reciprocal: kelvin = 1,000,000 / mireds
static NSInteger KelvinFromMireds(NSNumber *mireds) {
    return mireds.doubleValue > 0 ? (NSInteger)lround(1000000.0 / mireds.doubleValue) : 0;
}

- (NSInteger)minColorTemperatureKelvin {
    NSNumber *k = [self attribute:@"min_color_temp_kelvin" ofClass:[NSNumber class]];
    if (k) return k.integerValue;
    NSInteger fromMireds = KelvinFromMireds([self attribute:@"max_mireds" ofClass:[NSNumber class]]);
    return fromMireds > 0 ? fromMireds : 2000;
}

- (NSInteger)maxColorTemperatureKelvin {
    NSNumber *k = [self attribute:@"max_color_temp_kelvin" ofClass:[NSNumber class]];
    if (k) return k.integerValue;
    NSInteger fromMireds = KelvinFromMireds([self attribute:@"min_mireds" ofClass:[NSNumber class]]);
    return fromMireds > 0 ? fromMireds : 6500;
}

- (NSInteger)colorTemperatureKelvin {
    NSNumber *k = [self attribute:@"color_temp_kelvin" ofClass:[NSNumber class]];
    if (k) return k.integerValue;
    return KelvinFromMireds([self attribute:@"color_temp" ofClass:[NSNumber class]]);
}

- (NSInteger)brightness {
    // Home Assistant brightness is 0-255, convert to 0-100
    if (!self.attributes || ![self.attributes isKindOfClass:[NSDictionary class]]) {
        return self.isOn ? 100 : 0;
    }

    id brightnessValue = self.attributes[@"brightness"];
    if (brightnessValue && [brightnessValue isKindOfClass:[NSNumber class]]) {
        return (NSInteger)([brightnessValue floatValue] / 255.0 * 100.0);
    }
    return self.isOn ? 100 : 0;
}

@end
