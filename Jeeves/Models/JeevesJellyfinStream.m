#import "JeevesJellyfinStream.h"

@implementation JeevesJellyfinStream

+ (instancetype)streamFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    JeevesJellyfinStream *s = [[JeevesJellyfinStream alloc] init];
    id idx = dict[@"Index"];
    s.index = [idx isKindOfClass:[NSNumber class]] ? [idx integerValue] : -1;

    NSString *type = dict[@"Type"];
    if ([type isEqualToString:@"Video"])         s.streamType = JeevesJellyfinStreamTypeVideo;
    else if ([type isEqualToString:@"Audio"])    s.streamType = JeevesJellyfinStreamTypeAudio;
    else if ([type isEqualToString:@"Subtitle"]) s.streamType = JeevesJellyfinStreamTypeSubtitle;
    else s.streamType = JeevesJellyfinStreamTypeUnknown;

    s.language     = dict[@"Language"];
    s.displayTitle = dict[@"DisplayTitle"] ?: dict[@"Title"] ?: s.language ?: @"";
    return s;
}

@end
