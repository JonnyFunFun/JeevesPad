#import "HAWebSocketClient.h"
#import "HAAPIClient.h"
#import "JeevesWebSocket.h"

static const NSTimeInterval kCommandTimeout = 20.0;
static const NSInteger kCommandMessageId = 1;

// A single command's connection; keeps itself alive until it completes
@interface HAWebSocketCommand : NSObject <JeevesWebSocketDelegate>
@property (nonatomic, strong) JeevesWebSocket *socket;
@property (nonatomic, copy) NSDictionary *command;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) void (^completion)(id result, NSError *error);
@end

static NSMutableSet<HAWebSocketCommand *> *ActiveCommands(void) {
    static NSMutableSet *commands = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        commands = [NSMutableSet set];
    });
    return commands;
}

static NSError *HAWebSocketError(NSString *code, NSString *message) {
    return [NSError errorWithDomain:@"HAWebSocketClient" code:0
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error", @"code": code ?: @""}];
}

@implementation HAWebSocketCommand

- (void)start {
    [ActiveCommands() addObject:self];
    self.socket.delegate = self;
    [self.socket open];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCommandTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf finishWithResult:nil error:HAWebSocketError(@"timeout", @"Home Assistant didn't respond")];
    });
}

- (void)finishWithResult:(id)result error:(NSError *)error {
    if (!self.completion) return; // already finished
    void (^completion)(id, NSError *) = self.completion;
    self.completion = nil;
    self.socket.delegate = nil;
    [self.socket close];
    completion(result, error);
    // Usually called from inside the socket's own callbacks: release ourselves (and
    // with us the socket) on the next run loop turn, not while it's still running
    dispatch_async(dispatch_get_main_queue(), ^{
        [ActiveCommands() removeObject:self];
    });
}

- (void)sendJSON:(NSDictionary *)object {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    [self.socket sendText:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}

#pragma mark - JeevesWebSocketDelegate

- (void)webSocketDidOpen:(JeevesWebSocket *)webSocket {
    // Home Assistant speaks first (auth_required)
}

- (void)webSocket:(JeevesWebSocket *)webSocket didReceiveMessage:(NSString *)message {
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![msg isKindOfClass:[NSDictionary class]]) return;
    NSString *type = msg[@"type"];

    if ([type isEqualToString:@"auth_required"]) {
        [self sendJSON:@{@"type": @"auth", @"access_token": self.accessToken ?: @""}];
    } else if ([type isEqualToString:@"auth_invalid"]) {
        [self finishWithResult:nil error:HAWebSocketError(@"auth_invalid", @"Home Assistant rejected the access token")];
    } else if ([type isEqualToString:@"auth_ok"]) {
        NSMutableDictionary *command = [self.command mutableCopy];
        command[@"id"] = @(kCommandMessageId);
        [self sendJSON:command];
    } else if ([type isEqualToString:@"result"] && [msg[@"id"] integerValue] == kCommandMessageId) {
        if ([msg[@"success"] boolValue]) {
            id result = msg[@"result"];
            [self finishWithResult:([result isKindOfClass:[NSNull class]] ? nil : result) error:nil];
        } else {
            NSDictionary *err = [msg[@"error"] isKindOfClass:[NSDictionary class]] ? msg[@"error"] : nil;
            [self finishWithResult:nil error:HAWebSocketError(err[@"code"], err[@"message"] ?: @"Command failed")];
        }
    }
}

- (void)webSocket:(JeevesWebSocket *)webSocket didFailWithError:(NSError *)error {
    [self finishWithResult:nil error:error];
}

- (void)webSocketDidClose:(JeevesWebSocket *)webSocket {
    [self finishWithResult:nil error:HAWebSocketError(@"closed", @"Connection to Home Assistant closed")];
}

@end

@implementation HAWebSocketClient

+ (NSURL *)webSocketURL {
    NSString *base = [HAAPIClient sharedClient].baseURL;
    NSURLComponents *components = [NSURLComponents componentsWithString:base ?: @""];
    if (!components.host) return nil;
    components.scheme = [components.scheme.lowercaseString isEqualToString:@"https"] ? @"wss" : @"ws";
    NSString *path = components.path ?: @"";
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    components.path = [path stringByAppendingString:@"/api/websocket"];
    return components.URL;
}

+ (void)sendCommand:(NSDictionary *)command completion:(void (^)(id, NSError *))completion {
    HAAPIClient *api = [HAAPIClient sharedClient];
    NSURL *url = [self webSocketURL];
    if (![api isConfigured] || !url) {
        completion(nil, HAWebSocketError(@"not_configured", @"Home Assistant isn't configured"));
        return;
    }
    HAWebSocketCommand *request = [[HAWebSocketCommand alloc] init];
    request.socket = [[JeevesWebSocket alloc] initWithURL:url];
    request.command = command;
    request.accessToken = api.accessToken;
    request.completion = completion;
    [request start];
}

+ (void)fetchDashboardsWithCompletion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    [self sendCommand:@{@"type": @"lovelace/dashboards/list"} completion:^(id result, NSError *error) {
        completion([result isKindOfClass:[NSArray class]] ? result : (error ? nil : @[]), error);
    }];
}

+ (void)fetchLovelaceConfigForDashboard:(NSString *)urlPath completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableDictionary *command = [@{@"type": @"lovelace/config"} mutableCopy];
    if (urlPath.length > 0) command[@"url_path"] = urlPath;
    [self sendCommand:command completion:^(id result, NSError *error) {
        if (!error && ![result isKindOfClass:[NSDictionary class]]) {
            error = HAWebSocketError(@"invalid_config", @"Unexpected dashboard configuration");
        }
        completion(error ? nil : result, error);
    }];
}

@end
