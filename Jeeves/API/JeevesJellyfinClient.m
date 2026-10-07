#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinTarget.h"
#import "JeevesJellyfinSession.h"

NSString * const JellyfinSettingsChangedNotification = @"JellyfinSettingsChangedNotification";

static NSString * const kDefaultsJellyfinEnabled        = @"JellyfinEnabled";
static NSString * const kDefaultsJellyfinServerURL      = @"JellyfinServerURL";
static NSString * const kDefaultsJellyfinAccessToken    = @"JellyfinAccessToken";
static NSString * const kDefaultsJellyfinUserId         = @"JellyfinUserId";
static NSString * const kDefaultsJellyfinUserName       = @"JellyfinUserName";
static NSString * const kDefaultsJellyfinDeviceId       = @"JellyfinDeviceId";
static NSString * const kDefaultsJellyfinTargetName     = @"JellyfinTargetName";
static NSString * const kDefaultsJellyfinTargetDeviceId = @"JellyfinTargetDeviceId";

static NSString * const kItemFields = @"Overview";
static const long long kTicksPerMs = 10000;
// Sessions idle longer than this are not offered as targets / now playing
static const NSInteger kActiveSessionWindowSeconds = 960;

@interface JeevesJellyfinClient () <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSCache *imageCache;
@property (nonatomic, copy, readwrite)   NSString *serverURL;
@property (nonatomic, copy, readwrite)   NSString *accessToken;
@property (nonatomic, copy, readwrite)   NSString *userId;
@property (nonatomic, copy, readwrite)   NSString *userName;
@property (nonatomic, copy, readwrite)   NSString *deviceId;
@property (nonatomic, strong, readwrite) JeevesJellyfinTarget *currentTarget;
@end

@implementation JeevesJellyfinClient

+ (instancetype)sharedClient {
    static JeevesJellyfinClient *sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedClient = [[self alloc] init];
    });
    return sharedClient;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];

        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 200;
        _imageCache.totalCostLimit = 64 * 1024 * 1024;

        [self reloadFromDefaults];
    }
    return self;
}

- (void)reloadFromDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _enabled     = [d boolForKey:kDefaultsJellyfinEnabled];
    _serverURL   = [d stringForKey:kDefaultsJellyfinServerURL];
    _accessToken = [d stringForKey:kDefaultsJellyfinAccessToken];
    _userId      = [d stringForKey:kDefaultsJellyfinUserId];
    _userName    = [d stringForKey:kDefaultsJellyfinUserName];

    // Persistent per-install device ID; Jellyfin ties access tokens to it
    _deviceId = [d stringForKey:kDefaultsJellyfinDeviceId];
    if (_deviceId.length == 0) {
        _deviceId = [[NSUUID UUID] UUIDString];
        [d setObject:_deviceId forKey:kDefaultsJellyfinDeviceId];
        [d synchronize];
    }

    NSString *targetName     = [d stringForKey:kDefaultsJellyfinTargetName];
    NSString *targetDeviceId = [d stringForKey:kDefaultsJellyfinTargetDeviceId];
    if (targetDeviceId.length > 0) {
        JeevesJellyfinTarget *t = [[JeevesJellyfinTarget alloc] init];
        t.name = targetName;
        t.deviceId = targetDeviceId;
        _currentTarget = t;
    } else {
        _currentTarget = nil;
    }
}

- (void)saveTargetToDefaults:(JeevesJellyfinTarget *)target {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (target) {
        [d setObject:target.name     ?: @"" forKey:kDefaultsJellyfinTargetName];
        [d setObject:target.deviceId ?: @"" forKey:kDefaultsJellyfinTargetDeviceId];
    } else {
        [d removeObjectForKey:kDefaultsJellyfinTargetName];
        [d removeObjectForKey:kDefaultsJellyfinTargetDeviceId];
    }
    [d synchronize];
    self.currentTarget = target;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDefaultsJellyfinEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isConfigured {
    return self.serverURL.length > 0 && self.accessToken.length > 0 && self.userId.length > 0;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

#pragma mark - Headers

- (NSString *)authorizationHeader {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *device  = [[UIDevice currentDevice].model stringByReplacingOccurrencesOfString:@"\"" withString:@""] ?: @"iOS";
    NSMutableString *h = [NSMutableString stringWithFormat:@"MediaBrowser Client=\"Jeeves\", Device=\"%@\", DeviceId=\"%@\", Version=\"%@\"",
                          device, self.deviceId, version];
    if (self.accessToken.length > 0) {
        [h appendFormat:@", Token=\"%@\"", self.accessToken];
    }
    return h;
}

#pragma mark - Request builder

+ (NSString *)percentEncode:(NSString *)s {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~,"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

- (NSMutableURLRequest *)requestWithPath:(NSString *)path
                                   query:(NSDictionary *)query
                                  method:(NSString *)method {
    NSMutableString *urlStr = [NSMutableString stringWithFormat:@"%@%@", self.serverURL ?: @"", path];
    if (query.count > 0) {
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *k in query) {
            id v = query[k];
            NSString *vs = [v isKindOfClass:[NSString class]] ? v : [v description];
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, [[self class] percentEncode:vs]]];
        }
        [urlStr appendFormat:@"?%@", [pairs componentsJoinedByString:@"&"]];
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = method ?: @"GET";
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:[self authorizationHeader] forHTTPHeaderField:@"Authorization"];
    return req;
}

- (void)setJSONBody:(NSDictionary *)body onRequest:(NSMutableURLRequest *)req {
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
}

#pragma mark - Dispatch helper

- (void)runJSONRequest:(NSURLRequest *)req completion:(void(^)(id _Nullable jsonRoot, NSError * _Nullable error))completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSString *msg = (http.statusCode == 401)
                ? @"Not authorized (sign in again)"
                : [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode];
            NSError *err = [NSError errorWithDomain:@"JeevesJellyfinClient" code:http.statusCode userInfo:@{NSLocalizedDescriptionKey: msg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, err);
            });
            return;
        }
        id json = nil;
        NSError *parseError = nil;
        if (data.length > 0) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(parseError ? nil : json, parseError);
        });
    }];
    [task resume];
}

// Jellyfin list endpoints return either a QueryResult ({Items: [...]}) or a bare array
- (NSArray<JeevesJellyfinItem *> *)itemsFromResponse:(id)json {
    NSArray *raw = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        raw = json;
    } else if ([json isKindOfClass:[NSDictionary class]] && [json[@"Items"] isKindOfClass:[NSArray class]]) {
        raw = json[@"Items"];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        JeevesJellyfinItem *i = [JeevesJellyfinItem itemFromDictionary:d];
        if (i) [out addObject:i];
    }
    return out;
}

- (void)fetchItemsAtPath:(NSString *)path query:(NSDictionary *)query completion:(JeevesJellyfinItemsBlock)completion {
    if (![self isConfigured]) { if (completion) completion(nil, [self notConfiguredError]); return; }
    NSURLRequest *req = [self requestWithPath:path query:query method:@"GET"];
    [self runJSONRequest:req completion:^(id json, NSError *err) {
        if (err) { if (completion) completion(nil, err); return; }
        if (completion) completion([self itemsFromResponse:json], nil);
    }];
}

#pragma mark - Auth

- (void)signInToServer:(NSString *)serverURL
              username:(NSString *)username
              password:(NSString *)password
            completion:(void (^)(BOOL, NSError *))completion {
    while ([serverURL hasSuffix:@"/"]) {
        serverURL = [serverURL substringToIndex:serverURL.length - 1];
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:serverURL forKey:kDefaultsJellyfinServerURL];
    [d removeObjectForKey:kDefaultsJellyfinAccessToken];
    [d removeObjectForKey:kDefaultsJellyfinUserId];
    [d synchronize];
    [self reloadFromDefaults];

    NSMutableURLRequest *req = [self requestWithPath:@"/Users/AuthenticateByName" query:nil method:@"POST"];
    [self setJSONBody:@{@"Username": username ?: @"", @"Pw": password ?: @""} onRequest:req];
    [self runJSONRequest:req completion:^(id json, NSError *err) {
        NSDictionary *user = [json isKindOfClass:[NSDictionary class]] ? json[@"User"] : nil;
        NSString *token    = [json isKindOfClass:[NSDictionary class]] ? json[@"AccessToken"] : nil;
        if (err || ![user isKindOfClass:[NSDictionary class]] || token.length == 0) {
            if (completion) completion(NO, err ?: [NSError errorWithDomain:@"JeevesJellyfinClient" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unexpected sign-in response"}]);
            return;
        }
        [d setObject:token forKey:kDefaultsJellyfinAccessToken];
        [d setObject:user[@"Id"] ?: @"" forKey:kDefaultsJellyfinUserId];
        [d setObject:user[@"Name"] ?: username forKey:kDefaultsJellyfinUserName];
        [d synchronize];
        [self reloadFromDefaults];
        if (completion) completion(YES, nil);
    }];
}

#pragma mark - Browse

- (void)fetchLibrariesWithCompletion:(JeevesJellyfinLibrariesBlock)completion {
    if (![self isConfigured]) { if (completion) completion(nil, [self notConfiguredError]); return; }
    NSURLRequest *req = [self requestWithPath:@"/UserViews" query:@{@"userId": self.userId} method:@"GET"];
    [self runJSONRequest:req completion:^(id json, NSError *err) {
        if (err) { if (completion) completion(nil, err); return; }
        id items = [json isKindOfClass:[NSDictionary class]] ? json[@"Items"] : nil;
        if (completion) completion([items isKindOfClass:[NSArray class]] ? items : @[], nil);
    }];
}

- (void)fetchItemsInLibrary:(NSString *)libraryId
             collectionType:(NSString *)collectionType
                 startIndex:(NSInteger)start
                      limit:(NSInteger)limit
                 completion:(JeevesJellyfinItemsBlock)completion {
    NSMutableDictionary *q = [@{
        @"userId":     self.userId ?: @"",
        @"parentId":   libraryId ?: @"",
        @"sortBy":     @"DateCreated,SortName",
        @"sortOrder":  @"Descending",
        @"startIndex": @(start),
        @"limit":      @(limit > 0 ? limit : 50),
        @"fields":     kItemFields,
    } mutableCopy];

    // Libraries are folder trees; list the top-level media type rather than raw folders
    NSDictionary *typesByCollection = @{
        @"movies":      @"Movie",
        @"tvshows":     @"Series",
        @"music":       @"MusicAlbum",
        @"musicvideos": @"MusicVideo",
        @"boxsets":     @"BoxSet",
    };
    NSString *types = collectionType ? typesByCollection[collectionType] : nil;
    if (types) {
        q[@"includeItemTypes"] = types;
        q[@"recursive"] = @"true";
    }
    [self fetchItemsAtPath:@"/Items" query:q completion:completion];
}

- (void)fetchContinueWatchingWithCompletion:(JeevesJellyfinItemsBlock)completion {
    if (![self isConfigured]) { if (completion) completion(nil, [self notConfiguredError]); return; }
    // In-progress items followed by next-up episodes
    NSDictionary *resumeQuery = @{@"userId": self.userId, @"limit": @20, @"mediaTypes": @"Video", @"fields": kItemFields};
    [self fetchItemsAtPath:@"/UserItems/Resume" query:resumeQuery completion:^(NSArray *resume, NSError *resumeErr) {
        NSDictionary *nextUpQuery = @{@"userId": self.userId, @"limit": @20, @"fields": kItemFields};
        [self fetchItemsAtPath:@"/Shows/NextUp" query:nextUpQuery completion:^(NSArray *nextUp, NSError *nextUpErr) {
            if (!resume && !nextUp) { if (completion) completion(nil, resumeErr ?: nextUpErr); return; }
            NSMutableArray *out = [NSMutableArray arrayWithArray:resume ?: @[]];
            NSMutableSet *seen = [NSMutableSet set];
            for (JeevesJellyfinItem *i in out) {
                if (i.itemId) [seen addObject:i.itemId];
                if (i.seriesId) [seen addObject:i.seriesId];
            }
            for (JeevesJellyfinItem *i in nextUp) {
                if ((i.itemId && [seen containsObject:i.itemId]) || (i.seriesId && [seen containsObject:i.seriesId])) continue;
                [out addObject:i];
            }
            if (completion) completion(out, nil);
        }];
    }];
}

- (void)fetchRecentlyAddedWithCompletion:(JeevesJellyfinItemsBlock)completion {
    NSDictionary *q = @{@"userId": self.userId ?: @"", @"limit": @20, @"fields": kItemFields};
    [self fetchItemsAtPath:@"/Items/Latest" query:q completion:completion];
}

- (void)fetchItemWithId:(NSString *)itemId completion:(void(^)(JeevesJellyfinItem * _Nullable item, NSError * _Nullable error))completion {
    if (![self isConfigured]) { if (completion) completion(nil, [self notConfiguredError]); return; }
    NSString *path = [NSString stringWithFormat:@"/Items/%@", itemId];
    NSURLRequest *req = [self requestWithPath:path query:@{@"userId": self.userId} method:@"GET"];
    [self runJSONRequest:req completion:^(id json, NSError *err) {
        if (err) { if (completion) completion(nil, err); return; }
        if (completion) completion([JeevesJellyfinItem itemFromDictionary:json], nil);
    }];
}

- (void)fetchChildrenOfItem:(JeevesJellyfinItem *)item completion:(JeevesJellyfinItemsBlock)completion {
    NSString *uid = self.userId ?: @"";
    switch (item.type) {
        case JeevesJellyfinItemTypeSeries: {
            NSString *path = [NSString stringWithFormat:@"/Shows/%@/Seasons", item.itemId];
            [self fetchItemsAtPath:path query:@{@"userId": uid, @"fields": kItemFields} completion:completion];
            break;
        }
        case JeevesJellyfinItemTypeSeason: {
            NSString *path = [NSString stringWithFormat:@"/Shows/%@/Episodes", item.seriesId ?: @""];
            NSDictionary *q = @{@"userId": uid, @"seasonId": item.itemId ?: @"", @"fields": kItemFields};
            [self fetchItemsAtPath:path query:q completion:completion];
            break;
        }
        default: {
            NSDictionary *q = @{@"userId": uid, @"parentId": item.itemId ?: @"", @"sortBy": @"SortName", @"fields": kItemFields};
            [self fetchItemsAtPath:@"/Items" query:q completion:completion];
            break;
        }
    }
}

- (void)searchQuery:(NSString *)query completion:(JeevesJellyfinItemsBlock)completion {
    if (query.length == 0) { if (completion) completion(@[], nil); return; }
    NSDictionary *q = @{
        @"userId":           self.userId ?: @"",
        @"searchTerm":       query,
        @"recursive":        @"true",
        @"includeItemTypes": @"Movie,Series,Episode,MusicArtist,MusicAlbum,Audio",
        @"limit":            @30,
        @"fields":           kItemFields,
    };
    [self fetchItemsAtPath:@"/Items" query:q completion:^(NSArray<JeevesJellyfinItem *> *items, NSError *err) {
        if (!items) { if (completion) completion(nil, err); return; }
        NSArray *order = @[@(JeevesJellyfinItemTypeMovie), @(JeevesJellyfinItemTypeSeries), @(JeevesJellyfinItemTypeEpisode),
                           @(JeevesJellyfinItemTypeMusicArtist), @(JeevesJellyfinItemTypeMusicAlbum), @(JeevesJellyfinItemTypeAudio)];
        NSArray *sorted = [items sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(JeevesJellyfinItem *a, JeevesJellyfinItem *b) {
            NSUInteger oa = [order indexOfObject:@(a.type)];
            NSUInteger ob = [order indexOfObject:@(b.type)];
            return oa < ob ? NSOrderedAscending : (oa > ob ? NSOrderedDescending : NSOrderedSame);
        }];
        if (completion) completion(sorted, nil);
    }];
}

#pragma mark - Sessions / targets

- (void)fetchControllableSessionsWithCompletion:(void(^)(NSArray<NSDictionary *> *sessions, NSError *error))completion {
    if (![self isConfigured]) { if (completion) completion(nil, [self notConfiguredError]); return; }
    NSDictionary *q = @{@"controllableByUserId": self.userId, @"activeWithinSeconds": @(kActiveSessionWindowSeconds)};
    NSURLRequest *req = [self requestWithPath:@"/Sessions" query:q method:@"GET"];
    [self runJSONRequest:req completion:^(id json, NSError *err) {
        if (err) { if (completion) completion(nil, err); return; }
        if (completion) completion([json isKindOfClass:[NSArray class]] ? json : @[], nil);
    }];
}

- (void)fetchAvailableTargetsWithCompletion:(JeevesJellyfinTargetsBlock)completion {
    [self fetchControllableSessionsWithCompletion:^(NSArray<NSDictionary *> *sessions, NSError *err) {
        if (!sessions) { if (completion) completion(nil, err); return; }
        NSMutableArray *targets = [NSMutableArray array];
        NSMutableSet *seenDevices = [NSMutableSet set];
        for (NSDictionary *d in sessions) {
            if (![d isKindOfClass:[NSDictionary class]] || ![d[@"SupportsRemoteControl"] boolValue]) continue;
            JeevesJellyfinTarget *t = [JeevesJellyfinTarget targetFromSessionDictionary:d];
            if (t.deviceId.length == 0 || [t.deviceId isEqualToString:self.deviceId] || [seenDevices containsObject:t.deviceId]) continue;
            [seenDevices addObject:t.deviceId];
            [targets addObject:t];
        }
        if (completion) completion(targets, nil);
    }];
}

- (void)fetchActiveSessionsWithCompletion:(JeevesJellyfinSessionsBlock)completion {
    [self fetchControllableSessionsWithCompletion:^(NSArray<NSDictionary *> *sessions, NSError *err) {
        if (!sessions) { if (completion) completion(nil, err); return; }
        NSString *targetDevice = self.currentTarget.deviceId;
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in sessions) {
            if (![d isKindOfClass:[NSDictionary class]]) continue;
            NSString *deviceId = d[@"DeviceId"];
            if (targetDevice.length > 0) {
                if (![deviceId isEqualToString:targetDevice]) continue;
                // Keep the target's session ID fresh for playback commands
                self.currentTarget.sessionId = d[@"Id"];
            }
            JeevesJellyfinSession *s = [JeevesJellyfinSession sessionFromDictionary:d];
            if (s) [out addObject:s];
        }
        if (completion) completion(out, nil);
    }];
}

#pragma mark - Playback

- (void)resolveTargetSessionWithCompletion:(void(^)(NSString *sessionId, NSError *error))completion {
    JeevesJellyfinTarget *target = self.currentTarget;
    [self fetchControllableSessionsWithCompletion:^(NSArray<NSDictionary *> *sessions, NSError *err) {
        if (!sessions) { completion(nil, err); return; }
        for (NSDictionary *d in sessions) {
            if ([d isKindOfClass:[NSDictionary class]] && [d[@"DeviceId"] isEqualToString:target.deviceId]) {
                target.sessionId = d[@"Id"];
                completion(target.sessionId, nil);
                return;
            }
        }
        completion(nil, [NSError errorWithDomain:@"JeevesJellyfinClient" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Playback target is offline"}]);
    }];
}

// Sends a command to the target's session. Session IDs change when the client
// reconnects, so a 404 triggers one re-resolve by device ID and a retry.
- (void)sendTargetCommandWithPathFormat:(NSString *)pathFormat
                                  query:(NSDictionary *)query
                                   body:(NSDictionary *)body
                             completion:(JeevesJellyfinCompletionBlock)completion {
    if (!self.currentTarget) { if (completion) completion(NO, nil, [self noTargetError]); return; }

    if (self.currentTarget.sessionId.length > 0) {
        [self sendCommandToSession:self.currentTarget.sessionId pathFormat:pathFormat query:query body:body allowRetry:YES completion:completion];
    } else {
        [self resolveTargetSessionWithCompletion:^(NSString *sid, NSError *err) {
            if (sid) [self sendCommandToSession:sid pathFormat:pathFormat query:query body:body allowRetry:NO completion:completion];
            else if (completion) completion(NO, nil, err);
        }];
    }
}

- (void)sendCommandToSession:(NSString *)sessionId
                  pathFormat:(NSString *)pathFormat
                       query:(NSDictionary *)query
                        body:(NSDictionary *)body
                  allowRetry:(BOOL)allowRetry
                  completion:(JeevesJellyfinCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:pathFormat, sessionId];
    NSMutableURLRequest *req = [self requestWithPath:path query:query method:@"POST"];
    if (body) [self setJSONBody:body onRequest:req];
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && status == 404 && allowRetry) {
                [self resolveTargetSessionWithCompletion:^(NSString *sid, NSError *resolveErr) {
                    if (sid) [self sendCommandToSession:sid pathFormat:pathFormat query:query body:body allowRetry:NO completion:completion];
                    else if (completion) completion(NO, nil, resolveErr);
                }];
                return;
            }
            BOOL success = !error && status >= 200 && status < 300;
            if (completion) completion(success, data, error);
        });
    }];
    [task resume];
}

- (void)sendPlaystateCommand:(NSString *)command query:(NSDictionary *)query completion:(JeevesJellyfinCompletionBlock)completion {
    NSString *format = [NSString stringWithFormat:@"/Sessions/%%@/Playing/%@", command];
    [self sendTargetCommandWithPathFormat:format query:query body:nil completion:completion];
}

- (void)sendGeneralCommand:(NSString *)name arguments:(NSDictionary *)arguments completion:(JeevesJellyfinCompletionBlock)completion {
    NSDictionary *body = @{@"Name": name, @"Arguments": arguments ?: @{}};
    [self sendTargetCommandWithPathFormat:@"/Sessions/%@/Command" query:nil body:body completion:completion];
}

- (void)playMediaItem:(JeevesJellyfinItem *)item offset:(NSInteger)offsetMs completion:(JeevesJellyfinCompletionBlock)completion {
    NSDictionary *q = @{
        @"playCommand":        @"PlayNow",
        @"itemIds":            item.itemId ?: @"",
        @"startPositionTicks": @((long long)offsetMs * kTicksPerMs),
    };
    [self sendTargetCommandWithPathFormat:@"/Sessions/%@/Playing" query:q body:nil completion:completion];
}

- (void)playPauseWithCompletion:(JeevesJellyfinCompletionBlock)completion    { [self sendPlaystateCommand:@"PlayPause"     query:nil completion:completion]; }
- (void)stopWithCompletion:(JeevesJellyfinCompletionBlock)completion         { [self sendPlaystateCommand:@"Stop"          query:nil completion:completion]; }
- (void)skipNextWithCompletion:(JeevesJellyfinCompletionBlock)completion     { [self sendPlaystateCommand:@"NextTrack"     query:nil completion:completion]; }
- (void)skipPreviousWithCompletion:(JeevesJellyfinCompletionBlock)completion { [self sendPlaystateCommand:@"PreviousTrack" query:nil completion:completion]; }

- (void)seekToOffsetMs:(NSInteger)offsetMs completion:(JeevesJellyfinCompletionBlock)completion {
    [self sendPlaystateCommand:@"Seek" query:@{@"seekPositionTicks": @((long long)offsetMs * kTicksPerMs)} completion:completion];
}

- (void)setVolume:(CGFloat)volume completion:(JeevesJellyfinCompletionBlock)completion {
    NSInteger v = (NSInteger)round(volume * 100.0);
    if (v < 0) v = 0; if (v > 100) v = 100;
    [self sendGeneralCommand:@"SetVolume" arguments:@{@"Volume": [@(v) stringValue]} completion:completion];
}

- (void)setSubtitleStreamIndex:(NSInteger)index completion:(JeevesJellyfinCompletionBlock)completion {
    [self sendGeneralCommand:@"SetSubtitleStreamIndex" arguments:@{@"Index": [@(index) stringValue]} completion:completion];
}

- (void)setAudioStreamIndex:(NSInteger)index completion:(JeevesJellyfinCompletionBlock)completion {
    [self sendGeneralCommand:@"SetAudioStreamIndex" arguments:@{@"Index": [@(index) stringValue]} completion:completion];
}

#pragma mark - Images

- (NSString *)imageURLForThumbKey:(NSString *)thumbKey width:(NSInteger)w height:(NSInteger)h {
    if (thumbKey.length == 0 || self.serverURL.length == 0) return nil;
    NSString *sep = [thumbKey rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
    return [NSString stringWithFormat:@"%@%@%@maxWidth=%ld&maxHeight=%ld&quality=90",
            self.serverURL, thumbKey, sep, (long)w, (long)h];
}

- (NSURLSessionDataTask *)loadImageForThumbKey:(NSString *)thumbKey
                                          size:(CGSize)size
                                    completion:(JeevesJellyfinImageBlock)completion {
    if (thumbKey.length == 0) { if (completion) completion(nil, nil); return nil; }
    NSInteger w = (NSInteger)round(size.width  * [UIScreen mainScreen].scale);
    NSInteger h = (NSInteger)round(size.height * [UIScreen mainScreen].scale);
    NSString *url = [self imageURLForThumbKey:thumbKey width:w height:h];
    if (!url) { if (completion) completion(nil, nil); return nil; }

    UIImage *cached = [self.imageCache objectForKey:url];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(cached, nil);
        });
        return nil;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setValue:[self authorizationHeader] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"image/*" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            [self.imageCache setObject:img forKey:url cost:data.length];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(img, nil);
        });
    }];
    [task resume];
    return task;
}

#pragma mark - Errors

- (NSError *)notConfiguredError {
    return [NSError errorWithDomain:@"JeevesJellyfinClient" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not signed in to Jellyfin"}];
}

- (NSError *)noTargetError {
    return [NSError errorWithDomain:@"JeevesJellyfinClient" code:2 userInfo:@{NSLocalizedDescriptionKey: @"No Jellyfin playback target selected"}];
}

@end
