#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Bonjour service type advertised by every running Jeeves (also used by deploy_fleet.sh)
extern NSString * const JeevesFleetServiceType;
// Posted on the main thread when the list of discovered iPads changes
extern NSString * const JeevesFleetPeersDidChangeNotification;

@interface JeevesFleetPeer : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *hostName;
@property (nonatomic, copy, readonly, nullable) NSString *appVersion;
@property (nonatomic, assign, readonly) BOOL syncEnabled;
@end

// Discovers other iPads running Jeeves on the local network (Bonjour) and shares
// settings with them. Every message is encrypted and authenticated with the fleet
// code (JeevesFleetCrypto), so only iPads configured with the same code can push
// settings to this iPad or read its settings (which include the HA access token).
@interface JeevesFleetService : NSObject

+ (instancetype)sharedService;

- (void)start; // advertise this iPad and browse for others

@property (nonatomic, copy, readonly) NSArray<JeevesFleetPeer *> *peers;

// Sends this iPad's shared settings to the peer, which applies them
- (void)pushSettingsToPeer:(JeevesFleetPeer *)peer completion:(void (^)(BOOL success, NSString * _Nullable error))completion;
// Fetches the peer's shared settings and applies them here
- (void)pullSettingsFromPeer:(JeevesFleetPeer *)peer completion:(void (^)(BOOL success, NSString * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
