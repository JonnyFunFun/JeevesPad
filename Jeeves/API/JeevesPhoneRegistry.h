#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A phone registered with Home Assistant's Private BLE Device integration (which
// Bermuda picks up automatically for room-by-room tracking)
@interface JeevesRegisteredPhone : NSObject
@property (nonatomic, copy) NSString *entryId;      // config entry
@property (nonatomic, copy) NSString *irk;          // 32 hex characters, as Home Assistant stores it
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *deviceId; // device registry entry, once HA has created it
@end

// Registers phones' Identity Resolving Keys (IRKs) with Home Assistant, using the same
// config flow as Settings → Devices & Services → Add Integration → Private BLE Device.
// Needs an access token from an administrator. Errors are user-facing messages.
@interface JeevesPhoneRegistry : NSObject

// Home Assistant's form of a key (hex as given, or base64 as a Mac's Keychain shows it,
// which is stored byte-reversed), or nil if it isn't a 16-byte key. Accepts an "irk:"
// prefix and hex separated by spaces, colons, commas or dashes.
+ (nullable NSString *)normalizedIRKFromString:(NSString *)input;

+ (void)fetchPhonesWithCompletion:(void (^)(NSArray<JeevesRegisteredPhone *> * _Nullable phones, NSString * _Nullable error))completion;

// Home Assistant only accepts a key while it can see the phone, so the phone should be
// awake and near a Bluetooth proxy.
+ (void)registerPhoneWithKey:(NSString *)key
                        name:(NSString *)name
                  completion:(void (^)(JeevesRegisteredPhone * _Nullable phone, NSString * _Nullable error))completion;

// For keys found by pairing: tries each (most likely first) until Home Assistant finds
// the phone with one, and registers that one.
+ (void)registerPhoneWithCandidateKeys:(NSArray<NSString *> *)irks
                                  name:(NSString *)name
                            completion:(void (^)(JeevesRegisteredPhone * _Nullable phone, NSString * _Nullable error))completion;

+ (void)renamePhone:(JeevesRegisteredPhone *)phone to:(NSString *)name completion:(void (^)(NSString * _Nullable error))completion;
+ (void)removePhone:(JeevesRegisteredPhone *)phone completion:(void (^)(NSString * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
