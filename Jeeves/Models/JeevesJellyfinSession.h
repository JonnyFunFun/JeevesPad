#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class JeevesJellyfinItem;
@class JeevesJellyfinStream;

typedef NS_ENUM(NSInteger, JeevesJellyfinSessionState) {
    JeevesJellyfinSessionStateUnknown,
    JeevesJellyfinSessionStatePlaying,
    JeevesJellyfinSessionStatePaused
};

@interface JeevesJellyfinSession : NSObject

@property (nonatomic, strong) JeevesJellyfinItem *item;
@property (nonatomic, assign) JeevesJellyfinSessionState state;
@property (nonatomic, assign) NSInteger viewOffsetMs;
@property (nonatomic, assign) NSInteger durationMs;
@property (nonatomic, strong) NSArray<JeevesJellyfinStream *> *audioStreams;
@property (nonatomic, strong) NSArray<JeevesJellyfinStream *> *subtitleStreams;
@property (nonatomic, assign) NSInteger selectedAudioStreamIndex;    // -1 if unknown
@property (nonatomic, assign) NSInteger selectedSubtitleStreamIndex; // -1 if off/unknown
@property (nonatomic, assign) CGFloat volume; // 0..1

// Returns nil for sessions with nothing playing.
+ (instancetype)sessionFromDictionary:(NSDictionary *)dict;

@end
