#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class JeevesJellyfinItem;
@class JeevesJellyfinTarget;
@class JeevesJellyfinSession;

NS_ASSUME_NONNULL_BEGIN

typedef void (^JeevesJellyfinCompletionBlock)(BOOL success, id _Nullable result, NSError * _Nullable error);
typedef void (^JeevesJellyfinItemsBlock)(NSArray<JeevesJellyfinItem *> * _Nullable items, NSError * _Nullable error);
typedef void (^JeevesJellyfinLibrariesBlock)(NSArray<NSDictionary *> * _Nullable libraries, NSError * _Nullable error);
typedef void (^JeevesJellyfinTargetsBlock)(NSArray<JeevesJellyfinTarget *> * _Nullable targets, NSError * _Nullable error);
typedef void (^JeevesJellyfinSessionsBlock)(NSArray<JeevesJellyfinSession *> * _Nullable sessions, NSError * _Nullable error);
typedef void (^JeevesJellyfinImageBlock)(UIImage * _Nullable image, NSError * _Nullable error);

extern NSString * const JellyfinSettingsChangedNotification;

@interface JeevesJellyfinClient : NSObject

+ (instancetype)sharedClient;

@property (nonatomic, copy, readonly, nullable) NSString *serverURL;
@property (nonatomic, copy, readonly, nullable) NSString *accessToken;
@property (nonatomic, copy, readonly, nullable) NSString *userId;
@property (nonatomic, copy, readonly, nullable) NSString *userName;
@property (nonatomic, copy, readonly)           NSString *deviceId;
@property (nonatomic, strong, readonly, nullable) JeevesJellyfinTarget *currentTarget;
@property (nonatomic, assign) BOOL enabled;

- (BOOL)isConfigured;
- (void)reloadFromDefaults;
- (void)saveTargetToDefaults:(nullable JeevesJellyfinTarget *)target;

// Auth: exchanges username/password for an access token. Only the token and
// user ID are persisted.
- (void)signInToServer:(NSString *)serverURL
              username:(NSString *)username
              password:(NSString *)password
            completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

// Browse. Library dictionaries are raw Jellyfin views (`Id`, `Name`, `CollectionType`).
- (void)fetchLibrariesWithCompletion:(JeevesJellyfinLibrariesBlock)completion;
- (void)fetchItemsInLibrary:(NSString *)libraryId
             collectionType:(nullable NSString *)collectionType
                 startIndex:(NSInteger)start
                      limit:(NSInteger)limit
                 completion:(JeevesJellyfinItemsBlock)completion;
- (void)fetchContinueWatchingWithCompletion:(JeevesJellyfinItemsBlock)completion;
- (void)fetchRecentlyAddedWithCompletion:(JeevesJellyfinItemsBlock)completion;
- (void)fetchItemWithId:(NSString *)itemId completion:(void(^)(JeevesJellyfinItem * _Nullable item, NSError * _Nullable error))completion;
- (void)fetchChildrenOfItem:(JeevesJellyfinItem *)item completion:(JeevesJellyfinItemsBlock)completion;
- (void)searchQuery:(NSString *)query completion:(JeevesJellyfinItemsBlock)completion;

// Targets (remote-controllable client sessions)
- (void)fetchAvailableTargetsWithCompletion:(JeevesJellyfinTargetsBlock)completion;

// Sessions with something playing, filtered to the current target if one is set
- (void)fetchActiveSessionsWithCompletion:(JeevesJellyfinSessionsBlock)completion;

// Playback on the current target
- (void)playMediaItem:(JeevesJellyfinItem *)item offset:(NSInteger)offsetMs completion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)playPauseWithCompletion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)stopWithCompletion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)skipNextWithCompletion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)skipPreviousWithCompletion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)seekToOffsetMs:(NSInteger)offsetMs completion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)setVolume:(CGFloat)volume completion:(nullable JeevesJellyfinCompletionBlock)completion;
- (void)setSubtitleStreamIndex:(NSInteger)index completion:(nullable JeevesJellyfinCompletionBlock)completion; // -1 = off
- (void)setAudioStreamIndex:(NSInteger)index completion:(nullable JeevesJellyfinCompletionBlock)completion;

// Images. Thumb keys are the image paths produced by JeevesJellyfinItem.
- (nullable NSString *)imageURLForThumbKey:(NSString *)thumbKey width:(NSInteger)w height:(NSInteger)h;
- (nullable NSURLSessionDataTask *)loadImageForThumbKey:(NSString *)thumbKey
                                                   size:(CGSize)size
                                             completion:(JeevesJellyfinImageBlock)completion;

// Frees cached posters/backdrops (call when the Jellyfin UI closes). Also done
// automatically on memory warnings.
- (void)clearImageCache;

@end

NS_ASSUME_NONNULL_END
