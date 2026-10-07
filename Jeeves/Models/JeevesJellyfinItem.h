#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class JeevesJellyfinStream;

typedef NS_ENUM(NSInteger, JeevesJellyfinItemType) {
    JeevesJellyfinItemTypeUnknown,
    JeevesJellyfinItemTypeMovie,
    JeevesJellyfinItemTypeSeries,
    JeevesJellyfinItemTypeSeason,
    JeevesJellyfinItemTypeEpisode,
    JeevesJellyfinItemTypeVideo,
    JeevesJellyfinItemTypeMusicArtist,
    JeevesJellyfinItemTypeMusicAlbum,
    JeevesJellyfinItemTypeAudio
};

@interface JeevesJellyfinItem : NSObject

@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, assign) JeevesJellyfinItemType type;
@property (nonatomic, copy) NSString *typeString;      // Jellyfin BaseItemKind
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *seriesId;
@property (nonatomic, copy) NSString *seriesName;
@property (nonatomic, copy) NSString *albumArtist;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *thumb;           // own poster image key
@property (nonatomic, copy) NSString *art;             // backdrop image key (own or inherited)
@property (nonatomic, copy) NSString *seriesThumb;     // series/album poster image key
@property (nonatomic, assign) NSInteger durationMs;
@property (nonatomic, assign) NSInteger viewOffsetMs;
@property (nonatomic, assign) NSInteger year;
@property (nonatomic, assign) NSInteger index;         // episode/season/track number
@property (nonatomic, assign) NSInteger parentIndex;   // season number for episodes
@property (nonatomic, strong) NSArray<JeevesJellyfinStream *> *audioStreams;
@property (nonatomic, strong) NSArray<JeevesJellyfinStream *> *subtitleStreams;

+ (instancetype)itemFromDictionary:(NSDictionary *)dict;

- (NSString *)displayTitle;
- (NSString *)displaySubtitle;
- (CGFloat)progressFraction;     // 0.0 - 1.0
- (NSString *)preferredThumbKey; // best thumb for vertical poster

@end
