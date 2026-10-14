#import "JeevesWebSocket.h"
#import <CFNetwork/CFNetwork.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const kWebSocketGUID = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

typedef NS_ENUM(uint8_t, JeevesWebSocketOpcode) {
    JeevesWebSocketOpcodeContinuation = 0x0,
    JeevesWebSocketOpcodeText         = 0x1,
    JeevesWebSocketOpcodeBinary       = 0x2,
    JeevesWebSocketOpcodeClose        = 0x8,
    JeevesWebSocketOpcodePing         = 0x9,
    JeevesWebSocketOpcodePong         = 0xA,
};

@interface JeevesWebSocket () <NSStreamDelegate>
@property (nonatomic, strong, readwrite) NSURL *url;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *readBuffer;
@property (nonatomic, strong) NSMutableData *writeBuffer;
@property (nonatomic, strong) NSMutableData *messageBuffer; // fragments of the current message
@property (nonatomic, copy) NSString *secKey;
@property (nonatomic, assign) BOOL handshakeComplete;
@property (nonatomic, assign) BOOL closed;
@end

@implementation JeevesWebSocket

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
        _readBuffer = [NSMutableData data];
        _writeBuffer = [NSMutableData data];
    }
    return self;
}

- (void)dealloc {
    [self teardownStreams];
}

#pragma mark - Opening

- (void)open {
    // Delegate callbacks may release the last reference to this socket; stay alive
    // until this method returns (ARC doesn't retain self within its own methods)
    __attribute__((objc_precise_lifetime)) JeevesWebSocket *keepAlive = self;
    (void)keepAlive;

    BOOL secure = [self.url.scheme.lowercaseString isEqualToString:@"wss"];
    NSString *host = self.url.host ?: @"";
    UInt32 port = self.url.port ? self.url.port.unsignedIntValue : (secure ? 443 : 80);

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (__bridge CFStringRef)host, port, &readStream, &writeStream);
    self.inputStream = CFBridgingRelease(readStream);
    self.outputStream = CFBridgingRelease(writeStream);
    if (!self.inputStream || !self.outputStream) {
        [self failWithDescription:@"Could not create connection"];
        return;
    }

    if (secure) {
        [self.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        [self.outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        // Accept self-signed certificates, consistent with HAAPIClient
        NSDictionary *ssl = @{(__bridge NSString *)kCFStreamSSLValidatesCertificateChain: @NO,
                              (__bridge NSString *)kCFStreamSSLPeerName: host};
        [self.inputStream setProperty:ssl forKey:(__bridge NSString *)kCFStreamPropertySSLSettings];
        [self.outputStream setProperty:ssl forKey:(__bridge NSString *)kCFStreamPropertySSLSettings];
    }

    self.inputStream.delegate = self;
    self.outputStream.delegate = self;
    [self.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self.inputStream open];
    [self.outputStream open];

    // Queue the HTTP upgrade request; it's written once the socket has space
    uint8_t keyBytes[16];
    arc4random_buf(keyBytes, sizeof(keyBytes));
    self.secKey = [[NSData dataWithBytes:keyBytes length:sizeof(keyBytes)] base64EncodedStringWithOptions:0];

    NSString *path = self.url.path.length > 0 ? self.url.path : @"/";
    if (self.url.query.length > 0) path = [path stringByAppendingFormat:@"?%@", self.url.query];
    BOOL defaultPort = !self.url.port || (secure && port == 443) || (!secure && port == 80);
    NSString *hostHeader = defaultPort ? host : [NSString stringWithFormat:@"%@:%u", host, (unsigned int)port];
    NSString *request = [NSString stringWithFormat:
        @"GET %@ HTTP/1.1\r\n"
        @"Host: %@\r\n"
        @"Upgrade: websocket\r\n"
        @"Connection: Upgrade\r\n"
        @"Sec-WebSocket-Key: %@\r\n"
        @"Sec-WebSocket-Version: 13\r\n\r\n", path, hostHeader, self.secKey];
    [self.writeBuffer appendData:[request dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Sending

- (void)sendText:(NSString *)text {
    if (!self.handshakeComplete || self.closed) return;
    [self sendFrameWithOpcode:JeevesWebSocketOpcodeText payload:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendFrameWithOpcode:(JeevesWebSocketOpcode)opcode payload:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];
    uint8_t first = 0x80 | opcode; // FIN + opcode
    [frame appendBytes:&first length:1];

    // Client frames must be masked
    uint64_t length = payload.length;
    if (length < 126) {
        uint8_t b = 0x80 | (uint8_t)length;
        [frame appendBytes:&b length:1];
    } else if (length <= 0xFFFF) {
        uint8_t b[3] = {0x80 | 126, (uint8_t)(length >> 8), (uint8_t)length};
        [frame appendBytes:b length:3];
    } else {
        uint8_t b[9];
        b[0] = 0x80 | 127;
        for (int i = 0; i < 8; i++) b[1 + i] = (uint8_t)(length >> (56 - 8 * i));
        [frame appendBytes:b length:9];
    }

    uint8_t mask[4];
    arc4random_buf(mask, sizeof(mask));
    [frame appendBytes:mask length:4];

    NSMutableData *masked = [payload mutableCopy];
    uint8_t *bytes = masked.mutableBytes;
    for (NSUInteger i = 0; i < masked.length; i++) bytes[i] ^= mask[i % 4];
    [frame appendData:masked];

    [self.writeBuffer appendData:frame];
    [self flushWrites];
}

- (void)flushWrites {
    while (self.writeBuffer.length > 0 && self.outputStream.hasSpaceAvailable) {
        NSInteger written = [self.outputStream write:self.writeBuffer.bytes maxLength:self.writeBuffer.length];
        if (written <= 0) break;
        [self.writeBuffer replaceBytesInRange:NSMakeRange(0, written) withBytes:NULL length:0];
    }
}

#pragma mark - Closing

- (void)close {
    __attribute__((objc_precise_lifetime)) JeevesWebSocket *keepAlive = self;
    (void)keepAlive;
    if (self.closed) return;
    if (self.handshakeComplete) {
        [self sendFrameWithOpcode:JeevesWebSocketOpcodeClose payload:[NSData data]];
    }
    [self finishWithError:nil];
}

- (void)teardownStreams {
    for (NSStream *stream in @[self.inputStream ?: [NSNull null], self.outputStream ?: [NSNull null]]) {
        if ([stream isKindOfClass:[NSStream class]]) {
            stream.delegate = nil;
            [stream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            [stream close];
        }
    }
    self.inputStream = nil;
    self.outputStream = nil;
}

- (void)failWithDescription:(NSString *)description {
    [self finishWithError:[NSError errorWithDomain:@"JeevesWebSocket" code:1 userInfo:@{NSLocalizedDescriptionKey: description}]];
}

// Closes the connection and notifies the delegate exactly once
- (void)finishWithError:(NSError *)error {
    if (self.closed) return;
    self.closed = YES;
    [self teardownStreams];
    id<JeevesWebSocketDelegate> delegate = self.delegate;
    if (error) {
        [delegate webSocket:self didFailWithError:error];
    } else {
        [delegate webSocketDidClose:self];
    }
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    // Delivering a message can make the delegate drop its last reference to this
    // socket while frames are still being processed; stay alive until we return
    __attribute__((objc_precise_lifetime)) JeevesWebSocket *keepAlive = self;
    (void)keepAlive;

    switch (eventCode) {
        case NSStreamEventHasSpaceAvailable:
            [self flushWrites];
            break;
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[16384];
            while (self.inputStream.hasBytesAvailable) {
                NSInteger read = [self.inputStream read:buffer maxLength:sizeof(buffer)];
                if (read <= 0) break;
                [self.readBuffer appendBytes:buffer length:read];
            }
            [self processReadBuffer];
            break;
        }
        case NSStreamEventErrorOccurred:
            [self finishWithError:stream.streamError ?: [NSError errorWithDomain:@"JeevesWebSocket" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Connection error"}]];
            break;
        case NSStreamEventEndEncountered:
            [self finishWithError:nil];
            break;
        default:
            break;
    }
}

#pragma mark - Reading

- (void)processReadBuffer {
    if (!self.handshakeComplete) {
        NSData *terminator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange end = [self.readBuffer rangeOfData:terminator options:0 range:NSMakeRange(0, self.readBuffer.length)];
        if (end.location == NSNotFound) return;

        NSData *headerData = [self.readBuffer subdataWithRange:NSMakeRange(0, end.location)];
        [self.readBuffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(end)) withBytes:NULL length:0];
        NSString *headers = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
        if (![self validateHandshakeResponse:headers]) {
            NSString *statusLine = [[headers componentsSeparatedByString:@"\r\n"] firstObject] ?: @"no response";
            [self failWithDescription:[NSString stringWithFormat:@"WebSocket upgrade failed (%@)", statusLine]];
            return;
        }
        self.handshakeComplete = YES;
        [self.delegate webSocketDidOpen:self];
        if (self.closed) return;
    }
    [self processFrames];
}

- (BOOL)validateHandshakeResponse:(NSString *)headers {
    NSArray<NSString *> *lines = [headers componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0 || [lines[0] rangeOfString:@" 101"].location == NSNotFound) return NO;

    // Sec-WebSocket-Accept must be base64(SHA1(key + GUID))
    NSString *expectedInput = [self.secKey stringByAppendingString:kWebSocketGUID];
    NSData *inputData = [expectedInput dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(inputData.bytes, (CC_LONG)inputData.length, digest);
    NSString *expected = [[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH] base64EncodedStringWithOptions:0];

    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        if ([name isEqualToString:@"sec-websocket-accept"]) {
            NSString *value = [[line substringFromIndex:colon.location + 1]
                               stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [value isEqualToString:expected];
        }
    }
    return NO;
}

- (void)processFrames {
    while (!self.closed && self.readBuffer.length >= 2) {
        const uint8_t *bytes = self.readBuffer.bytes;
        BOOL fin = (bytes[0] & 0x80) != 0;
        JeevesWebSocketOpcode opcode = bytes[0] & 0x0F;
        BOOL masked = (bytes[1] & 0x80) != 0;
        uint64_t length = bytes[1] & 0x7F;
        NSUInteger offset = 2;

        if (length == 126) {
            if (self.readBuffer.length < 4) return;
            length = ((uint64_t)bytes[2] << 8) | bytes[3];
            offset = 4;
        } else if (length == 127) {
            if (self.readBuffer.length < 10) return;
            length = 0;
            for (int i = 0; i < 8; i++) length = (length << 8) | bytes[2 + i];
            offset = 10;
        }
        uint8_t mask[4] = {0, 0, 0, 0};
        if (masked) {
            if (self.readBuffer.length < offset + 4) return;
            memcpy(mask, bytes + offset, 4);
            offset += 4;
        }
        if (self.readBuffer.length < offset + length) return; // wait for the rest of the frame

        NSMutableData *payload = [[self.readBuffer subdataWithRange:NSMakeRange(offset, (NSUInteger)length)] mutableCopy];
        [self.readBuffer replaceBytesInRange:NSMakeRange(0, offset + (NSUInteger)length) withBytes:NULL length:0];
        if (masked) {
            uint8_t *p = payload.mutableBytes;
            for (NSUInteger i = 0; i < payload.length; i++) p[i] ^= mask[i % 4];
        }

        switch (opcode) {
            case JeevesWebSocketOpcodeText:
            case JeevesWebSocketOpcodeBinary:
                self.messageBuffer = payload;
                if (fin) [self deliverMessage];
                break;
            case JeevesWebSocketOpcodeContinuation:
                [self.messageBuffer appendData:payload];
                if (fin) [self deliverMessage];
                break;
            case JeevesWebSocketOpcodePing:
                [self sendFrameWithOpcode:JeevesWebSocketOpcodePong payload:payload];
                break;
            case JeevesWebSocketOpcodeClose:
                [self sendFrameWithOpcode:JeevesWebSocketOpcodeClose payload:[NSData data]];
                [self finishWithError:nil];
                break;
            default:
                break;
        }
    }
}

- (void)deliverMessage {
    NSData *data = self.messageBuffer;
    self.messageBuffer = nil;
    NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (message) [self.delegate webSocket:self didReceiveMessage:message];
}

@end
