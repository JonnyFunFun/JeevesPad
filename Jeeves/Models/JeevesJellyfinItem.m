#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinStream.h"

// Jellyfin durations/positions are in 100ns ticks
static const long long kTicksPerMs = 10000;

@implementation JeevesJellyfinItem

+ (instancetype)itemFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    JeevesJellyfinItem *item = [[JeevesJellyfinItem alloc] init];

    item.itemId      = [self stringFromDict:dict key:@"Id"];
    item.typeString  = [self stringFromDict:dict key:@"Type"];
    item.title       = [self stringFromDict:dict key:@"Name"];
    item.seriesId    = [self stringFromDict:dict key:@"SeriesId"];
    item.seriesName  = [self stringFromDict:dict key:@"SeriesName"];
    item.albumArtist = [self stringFromDict:dict key:@"AlbumArtist"];
    item.summary     = [self stringFromDict:dict key:@"Overview"];

    item.durationMs  = (NSInteger)([[self numberFromDict:dict key:@"RunTimeTicks"] longLongValue] / kTicksPerMs);
    item.year        = [[self numberFromDict:dict key:@"ProductionYear"] integerValue];
    item.index       = [[self numberFromDict:dict key:@"IndexNumber"] integerValue];
    item.parentIndex = [[self numberFromDict:dict key:@"ParentIndexNumber"] integerValue];

    NSDictionary *userData = dict[@"UserData"];
    if ([userData isKindOfClass:[NSDictionary class]]) {
        item.viewOffsetMs = (NSInteger)([[self numberFromDict:userData key:@"PlaybackPositionTicks"] longLongValue] / kTicksPerMs);
    }

    item.type = [self typeFromString:item.typeString];

    // Poster: the item's own Primary image
    NSDictionary *imageTags = dict[@"ImageTags"];
    if ([imageTags isKindOfClass:[NSDictionary class]]) {
        item.thumb = [self imageKeyForItemId:item.itemId type:@"Primary" tag:[self stringFromDict:imageTags key:@"Primary"]];
    }

    // Series (or album) poster, used for episodes/tracks
    NSString *seriesTag = [self stringFromDict:dict key:@"SeriesPrimaryImageTag"];
    if (item.seriesId.length > 0 && seriesTag.length > 0) {
        item.seriesThumb = [self imageKeyForItemId:item.seriesId type:@"Primary" tag:seriesTag];
    } else {
        NSString *albumId  = [self stringFromDict:dict key:@"AlbumId"];
        NSString *albumTag = [self stringFromDict:dict key:@"AlbumPrimaryImageTag"];
        if (albumId.length > 0 && albumTag.length > 0) {
            item.seriesThumb = [self imageKeyForItemId:albumId type:@"Primary" tag:albumTag];
        }
    }

    // Backdrop: own, else inherited from parent (e.g. series for an episode)
    NSArray *backdrops = dict[@"BackdropImageTags"];
    NSArray *parentBackdrops = dict[@"ParentBackdropImageTags"];
    NSString *parentBackdropId = [self stringFromDict:dict key:@"ParentBackdropItemId"];
    if ([backdrops isKindOfClass:[NSArray class]] && backdrops.count > 0) {
        item.art = [self imageKeyForItemId:item.itemId type:@"Backdrop/0" tag:[backdrops[0] description]];
    } else if ([parentBackdrops isKindOfClass:[NSArray class]] && parentBackdrops.count > 0 && parentBackdropId.length > 0) {
        item.art = [self imageKeyForItemId:parentBackdropId type:@"Backdrop/0" tag:[parentBackdrops[0] description]];
    }

    // Audio/subtitle tracks (present on full item fetches and session NowPlayingItem)
    NSMutableArray *audio = [NSMutableArray array];
    NSMutableArray *subs  = [NSMutableArray array];
    NSArray *streams = dict[@"MediaStreams"];
    if ([streams isKindOfClass:[NSArray class]]) {
        for (NSDictionary *sd in streams) {
            JeevesJellyfinStream *st = [JeevesJellyfinStream streamFromDictionary:sd];
            if (st.streamType == JeevesJellyfinStreamTypeAudio)         [audio addObject:st];
            else if (st.streamType == JeevesJellyfinStreamTypeSubtitle) [subs addObject:st];
        }
    }
    item.audioStreams    = audio;
    item.subtitleStreams = subs;

    return item;
}

+ (NSString *)imageKeyForItemId:(NSString *)itemId type:(NSString *)type tag:(NSString *)tag {
    if (itemId.length == 0 || tag.length == 0) return nil;
    return [NSString stringWithFormat:@"/Items/%@/Images/%@?tag=%@", itemId, type, tag];
}

+ (NSString *)stringFromDict:(NSDictionary *)dict key:(NSString *)key {
    id v = dict[key];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
}

+ (NSNumber *)numberFromDict:(NSDictionary *)dict key:(NSString *)key {
    id v = dict[key];
    if ([v isKindOfClass:[NSNumber class]]) return v;
    if ([v isKindOfClass:[NSString class]]) return @([(NSString *)v longLongValue]);
    return @(0);
}

+ (JeevesJellyfinItemType)typeFromString:(NSString *)s {
    if (!s) return JeevesJellyfinItemTypeUnknown;
    if ([s isEqualToString:@"Movie"])       return JeevesJellyfinItemTypeMovie;
    if ([s isEqualToString:@"Series"])      return JeevesJellyfinItemTypeSeries;
    if ([s isEqualToString:@"Season"])      return JeevesJellyfinItemTypeSeason;
    if ([s isEqualToString:@"Episode"])     return JeevesJellyfinItemTypeEpisode;
    if ([s isEqualToString:@"Video"] ||
        [s isEqualToString:@"MusicVideo"])  return JeevesJellyfinItemTypeVideo;
    if ([s isEqualToString:@"MusicArtist"]) return JeevesJellyfinItemTypeMusicArtist;
    if ([s isEqualToString:@"MusicAlbum"])  return JeevesJellyfinItemTypeMusicAlbum;
    if ([s isEqualToString:@"Audio"])       return JeevesJellyfinItemTypeAudio;
    return JeevesJellyfinItemTypeUnknown;
}

- (NSString *)displayTitle {
    switch (self.type) {
        case JeevesJellyfinItemTypeEpisode:
        case JeevesJellyfinItemTypeSeason:
            if (self.seriesName.length > 0) return self.seriesName;
            return self.title ?: @"";
        default:
            return self.title ?: @"";
    }
}

- (NSString *)displaySubtitle {
    switch (self.type) {
        case JeevesJellyfinItemTypeEpisode: {
            NSString *se = [NSString stringWithFormat:@"S%ld · E%ld", (long)self.parentIndex, (long)self.index];
            if (self.title.length > 0) return [NSString stringWithFormat:@"%@ — %@", se, self.title];
            return se;
        }
        case JeevesJellyfinItemTypeSeason:
            return self.title ?: [NSString stringWithFormat:@"Season %ld", (long)self.index];
        case JeevesJellyfinItemTypeMovie:
        case JeevesJellyfinItemTypeSeries:
            if (self.year > 0) return [NSString stringWithFormat:@"%ld", (long)self.year];
            return @"";
        case JeevesJellyfinItemTypeMusicAlbum:
        case JeevesJellyfinItemTypeAudio:
            return self.albumArtist ?: @"";
        default:
            return @"";
    }
}

- (CGFloat)progressFraction {
    if (self.durationMs <= 0) return 0.0;
    CGFloat f = (CGFloat)self.viewOffsetMs / (CGFloat)self.durationMs;
    if (f < 0) f = 0;
    if (f > 1) f = 1;
    return f;
}

- (NSString *)preferredThumbKey {
    switch (self.type) {
        case JeevesJellyfinItemTypeEpisode:
        case JeevesJellyfinItemTypeAudio:
            return self.seriesThumb ?: self.thumb;
        default:
            return self.thumb ?: self.seriesThumb;
    }
}

@end
