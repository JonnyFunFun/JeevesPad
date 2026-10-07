#import <Foundation/Foundation.h>

// A remote-controllable Jellyfin client session. Session IDs change when the
// client reconnects, so targets are persisted by deviceId and the sessionId is
// re-resolved from /Sessions as needed.
@interface JeevesJellyfinTarget : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *client;   // e.g. "Jellyfin Media Player"

+ (instancetype)targetFromSessionDictionary:(NSDictionary *)dict;

@end
