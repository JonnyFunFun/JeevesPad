#import <Foundation/Foundation.h>

@class JeevesWebSocket;

NS_ASSUME_NONNULL_BEGIN

// Callbacks are delivered on the main thread
@protocol JeevesWebSocketDelegate <NSObject>
- (void)webSocketDidOpen:(JeevesWebSocket *)webSocket;
- (void)webSocket:(JeevesWebSocket *)webSocket didReceiveMessage:(NSString *)message;
- (void)webSocket:(JeevesWebSocket *)webSocket didFailWithError:(NSError *)error;
- (void)webSocketDidClose:(JeevesWebSocket *)webSocket;
@end

// Minimal RFC 6455 WebSocket client (text messages only) for iOS 9, which has no
// built-in WebSocket support. Supports ws:// and wss://; like the app's HTTP clients,
// it accepts self-signed certificates so local Home Assistant servers work.
@interface JeevesWebSocket : NSObject

- (instancetype)initWithURL:(NSURL *)url;

@property (nonatomic, weak, nullable) id<JeevesWebSocketDelegate> delegate;
@property (nonatomic, strong, readonly) NSURL *url;

- (void)open;
- (void)sendText:(NSString *)text;
- (void)close;

@end

NS_ASSUME_NONNULL_END
