#import "JeevesJellyfinSession.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinStream.h"

@implementation JeevesJellyfinSession

+ (instancetype)sessionFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *nowPlaying = dict[@"NowPlayingItem"];
    if (![nowPlaying isKindOfClass:[NSDictionary class]]) return nil;

    JeevesJellyfinSession *s = [[JeevesJellyfinSession alloc] init];
    s.item      = [JeevesJellyfinItem itemFromDictionary:nowPlaying];
    s.durationMs      = s.item.durationMs;
    s.audioStreams    = s.item.audioStreams;
    s.subtitleStreams = s.item.subtitleStreams;
    s.selectedAudioStreamIndex    = -1;
    s.selectedSubtitleStreamIndex = -1;
    s.volume = 1.0;

    NSDictionary *playState = dict[@"PlayState"];
    if ([playState isKindOfClass:[NSDictionary class]]) {
        s.state = [playState[@"IsPaused"] boolValue] ? JeevesJellyfinSessionStatePaused : JeevesJellyfinSessionStatePlaying;

        id pos = playState[@"PositionTicks"];
        if ([pos isKindOfClass:[NSNumber class]]) s.viewOffsetMs = (NSInteger)([pos longLongValue] / 10000);

        id audio = playState[@"AudioStreamIndex"];
        if ([audio isKindOfClass:[NSNumber class]]) s.selectedAudioStreamIndex = [audio integerValue];
        id sub = playState[@"SubtitleStreamIndex"];
        if ([sub isKindOfClass:[NSNumber class]]) s.selectedSubtitleStreamIndex = [sub integerValue];

        id vol = playState[@"VolumeLevel"];
        if ([vol isKindOfClass:[NSNumber class]]) s.volume = [vol floatValue] / 100.0;
    }

    return s;
}

@end
