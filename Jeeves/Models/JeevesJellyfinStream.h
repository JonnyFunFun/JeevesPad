#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, JeevesJellyfinStreamType) {
    JeevesJellyfinStreamTypeUnknown,
    JeevesJellyfinStreamTypeVideo,
    JeevesJellyfinStreamTypeAudio,
    JeevesJellyfinStreamTypeSubtitle
};

@interface JeevesJellyfinStream : NSObject

@property (nonatomic, assign) NSInteger index;          // Jellyfin MediaStream `Index`
@property (nonatomic, assign) JeevesJellyfinStreamType streamType;
@property (nonatomic, copy)   NSString *language;
@property (nonatomic, copy)   NSString *displayTitle;

+ (instancetype)streamFromDictionary:(NSDictionary *)dict;

@end
