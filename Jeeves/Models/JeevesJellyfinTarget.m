#import "JeevesJellyfinTarget.h"

@implementation JeevesJellyfinTarget

+ (instancetype)targetFromSessionDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    JeevesJellyfinTarget *t = [[JeevesJellyfinTarget alloc] init];
    t.name      = dict[@"DeviceName"] ?: dict[@"Client"];
    t.deviceId  = dict[@"DeviceId"];
    t.sessionId = dict[@"Id"];
    t.client    = dict[@"Client"];
    return t;
}

@end
