#import "JeevesFleetService.h"
#import "JeevesFleetSettings.h"
#import "JeevesFleetCrypto.h"
#import <UIKit/UIKit.h>

NSString * const JeevesFleetServiceType = @"_jeeves._tcp.";
NSString * const JeevesFleetPeersDidChangeNotification = @"JeevesFleetPeersDidChangeNotification";

static const NSInteger kProtocolVersion = 1;
static const NSUInteger kMaxMessageLength = 4 * 1024 * 1024;
static const NSTimeInterval kConnectionTimeout = 15.0;
static const NSTimeInterval kMaxClockSkew = 600; // reject messages older/newer than this (replay protection)

#pragma mark - Peer

@interface JeevesFleetPeer ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *hostName;
@property (nonatomic, copy, readwrite) NSString *appVersion;
@property (nonatomic, assign, readwrite) BOOL syncEnabled;
@property (nonatomic, strong) NSNetService *service;
@end

@implementation JeevesFleetPeer
@end

#pragma mark - Connection

// One request/response exchange over a pair of streams: each message is a 4-byte
// big-endian length followed by a binary property list
@interface JeevesFleetConnection : NSObject <NSStreamDelegate>
@property (nonatomic, strong) NSInputStream *input;
@property (nonatomic, strong) NSOutputStream *output;
@property (nonatomic, strong) NSMutableData *readBuffer;
@property (nonatomic, strong) NSMutableData *writeBuffer;
@property (nonatomic, assign) BOOL closeAfterWrite;
@property (nonatomic, copy) void (^messageHandler)(JeevesFleetConnection *connection, NSDictionary *message);
@property (nonatomic, copy) void (^failureHandler)(JeevesFleetConnection *connection, NSString *error);
@property (nonatomic, assign) BOOL finished;
@end

static NSMutableSet<JeevesFleetConnection *> *ActiveConnections(void) {
    static NSMutableSet *connections = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        connections = [NSMutableSet set];
    });
    return connections;
}

@implementation JeevesFleetConnection

- (instancetype)initWithInput:(NSInputStream *)input output:(NSOutputStream *)output {
    self = [super init];
    if (self) {
        _input = input;
        _output = output;
        _readBuffer = [NSMutableData data];
        _writeBuffer = [NSMutableData data];
    }
    return self;
}

- (void)open {
    [ActiveConnections() addObject:self]; // keep alive until finished
    for (NSStream *stream in @[self.input, self.output]) {
        stream.delegate = self;
        [stream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [stream open];
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kConnectionTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf failWithError:@"Timed out"];
    });
}

- (void)sendMessage:(NSDictionary *)message closeAfterward:(BOOL)close {
    NSData *body = [NSPropertyListSerialization dataWithPropertyList:message format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!body) { [self failWithError:@"Couldn't encode message"]; return; }
    uint32_t length = CFSwapInt32HostToBig((uint32_t)body.length);
    [self.writeBuffer appendBytes:&length length:sizeof(length)];
    [self.writeBuffer appendData:body];
    self.closeAfterWrite = close;
    [self flush];
}

- (void)flush {
    while (self.writeBuffer.length > 0 && self.output.hasSpaceAvailable) {
        NSInteger written = [self.output write:self.writeBuffer.bytes maxLength:self.writeBuffer.length];
        if (written <= 0) break;
        [self.writeBuffer replaceBytesInRange:NSMakeRange(0, written) withBytes:NULL length:0];
    }
    if (self.writeBuffer.length == 0 && self.closeAfterWrite) [self finish];
}

- (void)finish {
    if (self.finished) return;
    self.finished = YES;
    for (NSStream *stream in @[self.input ?: [NSNull null], self.output ?: [NSNull null]]) {
        if (![stream isKindOfClass:[NSStream class]]) continue;
        stream.delegate = nil;
        [stream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [stream close];
    }
    // Release on the next turn: we're usually inside a stream callback
    dispatch_async(dispatch_get_main_queue(), ^{
        [ActiveConnections() removeObject:self];
    });
}

- (void)failWithError:(NSString *)error {
    if (self.finished) return;
    void (^handler)(JeevesFleetConnection *, NSString *) = self.failureHandler;
    [self finish];
    if (handler) handler(self, error);
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    __attribute__((objc_precise_lifetime)) JeevesFleetConnection *keepAlive = self;
    (void)keepAlive;
    switch (eventCode) {
        case NSStreamEventHasSpaceAvailable:
            [self flush];
            break;
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[16384];
            while (self.input.hasBytesAvailable) {
                NSInteger read = [self.input read:buffer maxLength:sizeof(buffer)];
                if (read <= 0) break;
                [self.readBuffer appendBytes:buffer length:read];
            }
            [self processReadBuffer];
            break;
        }
        case NSStreamEventErrorOccurred:
            [self failWithError:stream.streamError.localizedDescription ?: @"Connection error"];
            break;
        case NSStreamEventEndEncountered:
            [self failWithError:@"Connection closed"];
            break;
        default:
            break;
    }
}

- (void)processReadBuffer {
    if (self.finished || self.readBuffer.length < 4) return;
    uint32_t length;
    memcpy(&length, self.readBuffer.bytes, 4);
    length = CFSwapInt32BigToHost(length);
    if (length > kMaxMessageLength) { [self failWithError:@"Message too large"]; return; }
    if (self.readBuffer.length < 4 + length) return;

    NSData *body = [self.readBuffer subdataWithRange:NSMakeRange(4, length)];
    [self.readBuffer replaceBytesInRange:NSMakeRange(0, 4 + length) withBytes:NULL length:0];
    id message = [NSPropertyListSerialization propertyListWithData:body options:NSPropertyListImmutable format:NULL error:nil];
    if (![message isKindOfClass:[NSDictionary class]]) { [self failWithError:@"Invalid message"]; return; }
    if (self.messageHandler) self.messageHandler(self, message);
}

@end

#pragma mark - Service

@interface JeevesFleetService () <NSNetServiceDelegate, NSNetServiceBrowserDelegate>
@property (nonatomic, strong) NSNetService *publishedService;
@property (nonatomic, copy) NSString *publishedName;
@property (nonatomic, strong) NSNetServiceBrowser *browser;
@property (nonatomic, strong) NSMutableArray<JeevesFleetPeer *> *mutablePeers;
@property (nonatomic, strong) JeevesFleetCrypto *crypto;
@property (nonatomic, copy) NSString *cryptoCode;
@end

@implementation JeevesFleetService

+ (instancetype)sharedService {
    static JeevesFleetService *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutablePeers = [NSMutableArray array];
    }
    return self;
}

- (NSArray<JeevesFleetPeer *> *)peers {
    return [self.mutablePeers copy];
}

- (NSString *)deviceName {
    return [UIDevice currentDevice].name ?: @"iPad";
}

- (NSString *)appVersion {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
}

// Key derivation is deliberately slow, so cache it per fleet code
- (JeevesFleetCrypto *)cryptoForCurrentCode {
    NSString *code = [JeevesFleetSettings sharedSettings].fleetCode;
    if (code.length == 0) return nil;
    if (![code isEqualToString:self.cryptoCode]) {
        self.crypto = [[JeevesFleetCrypto alloc] initWithFleetCode:code];
        self.cryptoCode = code;
    }
    return self.crypto;
}

#pragma mark - Advertising & browsing

- (void)start {
    if (self.publishedService) return;

    // Advertise even when sync is off, so deploy_fleet.sh can find this iPad
    self.publishedService = [[NSNetService alloc] initWithDomain:@"local." type:JeevesFleetServiceType name:[self deviceName] port:0];
    self.publishedService.delegate = self;
    [self.publishedService publishWithOptions:NSNetServiceListenForConnections];

    self.browser = [[NSNetServiceBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:JeevesFleetServiceType inDomain:@"local."];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTXTRecord)
                                                 name:JeevesFleetConfigurationDidChangeNotification object:nil];
}

- (void)updateTXTRecord {
    NSDictionary *txt = @{@"app": [@"Jeeves" dataUsingEncoding:NSUTF8StringEncoding],
                          @"ver": [[self appVersion] dataUsingEncoding:NSUTF8StringEncoding],
                          @"sync": [([JeevesFleetSettings sharedSettings].enabled ? @"1" : @"0") dataUsingEncoding:NSUTF8StringEncoding]};
    [self.publishedService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:txt]];
}

- (void)netServiceDidPublish:(NSNetService *)sender {
    if (sender != self.publishedService) return;
    self.publishedName = sender.name; // may differ from the device name if there was a clash
    [self updateTXTRecord];
    // Drop ourselves if the browser already reported us
    [self removePeersMatching:^BOOL(JeevesFleetPeer *peer) { return [peer.name isEqualToString:sender.name]; }];
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *, NSNumber *> *)errorDict {
    NSLog(@"[Fleet] Could not advertise: %@", errorDict);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    if ([service.name isEqualToString:self.publishedName]) return;
    for (JeevesFleetPeer *existing in self.mutablePeers) {
        if ([existing.name isEqualToString:service.name]) return;
    }
    JeevesFleetPeer *peer = [[JeevesFleetPeer alloc] init];
    peer.name = service.name;
    peer.service = service;
    [self.mutablePeers addObject:peer];
    [self.mutablePeers sortUsingComparator:^NSComparisonResult(JeevesFleetPeer *a, JeevesFleetPeer *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    // Resolve for the host name, and watch the TXT record for sync on/off
    service.delegate = self;
    [service resolveWithTimeout:10];
    [service startMonitoring];
    if (!moreComing) [self peersChanged];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    [self removePeersMatching:^BOOL(JeevesFleetPeer *peer) { return [peer.name isEqualToString:service.name]; }];
}

- (void)removePeersMatching:(BOOL (^)(JeevesFleetPeer *peer))predicate {
    NSIndexSet *matches = [self.mutablePeers indexesOfObjectsPassingTest:^BOOL(JeevesFleetPeer *peer, NSUInteger idx, BOOL *stop) {
        return predicate(peer);
    }];
    if (matches.count == 0) return;
    for (JeevesFleetPeer *peer in [self.mutablePeers objectsAtIndexes:matches]) {
        [peer.service stopMonitoring];
        peer.service.delegate = nil;
    }
    [self.mutablePeers removeObjectsAtIndexes:matches];
    [self peersChanged];
}

- (JeevesFleetPeer *)peerForService:(NSNetService *)service {
    for (JeevesFleetPeer *peer in self.mutablePeers) {
        if (peer.service == service) return peer;
    }
    return nil;
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    JeevesFleetPeer *peer = [self peerForService:sender];
    peer.hostName = sender.hostName;
    if (sender.TXTRecordData) [self applyTXTRecord:sender.TXTRecordData toPeer:peer];
    [self peersChanged];
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data {
    JeevesFleetPeer *peer = [self peerForService:sender];
    [self applyTXTRecord:data toPeer:peer];
    [self peersChanged];
}

- (void)applyTXTRecord:(NSData *)data toPeer:(JeevesFleetPeer *)peer {
    NSDictionary *txt = [NSNetService dictionaryFromTXTRecordData:data];
    NSString *(^string)(NSString *) = ^NSString *(NSString *key) {
        NSData *value = txt[key];
        return value ? [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding] : nil;
    };
    peer.appVersion = string(@"ver");
    peer.syncEnabled = [string(@"sync") isEqualToString:@"1"];
}

- (void)peersChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesFleetPeersDidChangeNotification object:self];
}

#pragma mark - Incoming requests

- (void)netService:(NSNetService *)sender didAcceptConnectionWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream {
    dispatch_async(dispatch_get_main_queue(), ^{
        JeevesFleetConnection *connection = [[JeevesFleetConnection alloc] initWithInput:inputStream output:outputStream];
        connection.messageHandler = ^(JeevesFleetConnection *conn, NSDictionary *message) {
            [conn sendMessage:[self responseToRequest:message] closeAfterward:YES];
        };
        [connection open];
    });
}

- (NSDictionary *)errorResponse:(NSString *)error {
    // Unencrypted: never contains settings
    return @{@"v": @(kProtocolVersion), @"type": @"result", @"error": error};
}

- (NSDictionary *)responseToRequest:(NSDictionary *)request {
    JeevesFleetSettings *settings = [JeevesFleetSettings sharedSettings];
    JeevesFleetCrypto *crypto = [self cryptoForCurrentCode];
    if (!settings.enabled || !crypto) {
        return [self errorResponse:[NSString stringWithFormat:@"Fleet sync is turned off on %@", [self deviceName]]];
    }

    NSDictionary *payload = [self openBox:request[@"box"] withCrypto:crypto];
    if (!payload) {
        return [self errorResponse:[NSString stringWithFormat:@"%@ has a different fleet code", [self deviceName]]];
    }
    NSString *error = [self validatePayload:payload];
    if (error) return [self errorResponse:error];

    NSString *type = request[@"type"];
    NSString *from = [payload[@"from"] isKindOfClass:[NSString class]] ? payload[@"from"] : @"another iPad";
    if ([type isEqualToString:@"push"]) {
        if (![payload[@"settings"] isKindOfClass:[NSDictionary class]] ||
            ![settings applySnapshot:payload[@"settings"] fromDevice:from]) {
            return [self errorResponse:@"Invalid settings"];
        }
        return [self sealedMessage:@{@"ok": @YES} type:@"result" crypto:crypto];
    }
    if ([type isEqualToString:@"pull"]) {
        return [self sealedMessage:@{@"ok": @YES, @"settings": [settings snapshot]} type:@"result" crypto:crypto];
    }
    return [self errorResponse:@"Unknown request"];
}

#pragma mark - Sealing

- (NSDictionary *)sealedMessage:(NSDictionary *)payload type:(NSString *)type crypto:(JeevesFleetCrypto *)crypto {
    NSMutableDictionary *body = [payload mutableCopy];
    body[@"ts"] = @([[NSDate date] timeIntervalSince1970]);
    body[@"from"] = [self deviceName];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:body format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return @{@"v": @(kProtocolVersion), @"type": type, @"box": [crypto seal:plist ?: [NSData data]]};
}

- (NSDictionary *)openBox:(id)box withCrypto:(JeevesFleetCrypto *)crypto {
    if (![box isKindOfClass:[NSData class]]) return nil;
    NSData *plist = [crypto open:box];
    if (!plist) return nil;
    id payload = [NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:NULL error:nil];
    return [payload isKindOfClass:[NSDictionary class]] ? payload : nil;
}

- (NSString *)validatePayload:(NSDictionary *)payload {
    NSTimeInterval ts = [payload[@"ts"] doubleValue];
    if (fabs([[NSDate date] timeIntervalSince1970] - ts) > kMaxClockSkew) {
        return @"Request expired (check both iPads' clocks)";
    }
    return nil;
}

#pragma mark - Outgoing requests

- (void)sendRequest:(NSString *)type
             toPeer:(JeevesFleetPeer *)peer
            payload:(NSDictionary *)payload
         completion:(void (^)(NSDictionary *response, NSString *error))completion {
    JeevesFleetCrypto *crypto = [self cryptoForCurrentCode];
    if (![JeevesFleetSettings sharedSettings].enabled || !crypto) {
        completion(nil, @"Turn on fleet sync and set the fleet code first");
        return;
    }
    NSInputStream *input = nil;
    NSOutputStream *output = nil;
    if (![peer.service getInputStream:&input outputStream:&output] || !input || !output) {
        completion(nil, [NSString stringWithFormat:@"Couldn't connect to %@", peer.name]);
        return;
    }

    JeevesFleetConnection *connection = [[JeevesFleetConnection alloc] initWithInput:input output:output];
    connection.messageHandler = ^(JeevesFleetConnection *conn, NSDictionary *message) {
        [conn finish];
        if ([message[@"error"] isKindOfClass:[NSString class]]) {
            completion(nil, message[@"error"]);
            return;
        }
        NSDictionary *response = [self openBox:message[@"box"] withCrypto:crypto];
        NSString *error = response ? [self validatePayload:response] : [NSString stringWithFormat:@"%@ has a different fleet code", peer.name];
        completion(error ? nil : response, error);
    };
    connection.failureHandler = ^(JeevesFleetConnection *conn, NSString *error) {
        completion(nil, [NSString stringWithFormat:@"%@: %@", peer.name, error]);
    };
    [connection open];
    [connection sendMessage:[self sealedMessage:payload type:type crypto:crypto] closeAfterward:NO];
}

- (void)pushSettingsToPeer:(JeevesFleetPeer *)peer completion:(void (^)(BOOL, NSString *))completion {
    NSDictionary *payload = @{@"settings": [[JeevesFleetSettings sharedSettings] snapshot]};
    [self sendRequest:@"push" toPeer:peer payload:payload completion:^(NSDictionary *response, NSString *error) {
        completion(response != nil && [response[@"ok"] boolValue], error);
    }];
}

- (void)pullSettingsFromPeer:(JeevesFleetPeer *)peer completion:(void (^)(BOOL, NSString *))completion {
    [self sendRequest:@"pull" toPeer:peer payload:@{} completion:^(NSDictionary *response, NSString *error) {
        NSDictionary *snapshot = response[@"settings"];
        if (!response || ![snapshot isKindOfClass:[NSDictionary class]]) {
            completion(NO, error ?: @"No settings received");
            return;
        }
        BOOL applied = [[JeevesFleetSettings sharedSettings] applySnapshot:snapshot fromDevice:peer.name];
        completion(applied, applied ? nil : @"Invalid settings");
    }];
}

@end
