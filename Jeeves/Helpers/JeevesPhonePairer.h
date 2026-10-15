#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class JeevesPhonePairer;

@protocol JeevesPhonePairerDelegate <NSObject>
// Advertising: the phone can now find and pair with this iPad
- (void)phonePairerIsWaitingForPhone:(JeevesPhonePairer *)pairer;
// The phone paired. `keys` are possible IRKs in Home Assistant's hex form, most likely
// first (Home Assistant confirms which one is right by finding the phone with it).
- (void)phonePairer:(JeevesPhonePairer *)pairer didPairWithKeys:(NSArray<NSString *> *)keys;
- (void)phonePairer:(JeevesPhonePairer *)pairer didFailWithError:(NSString *)error;
@end

// Gets a phone's Identity Resolving Key by pairing it with this iPad. The iPad
// advertises itself as a Bluetooth LE accessory ("Jeeves Pairing") with a characteristic
// that requires encryption, so connecting to it pairs; or the phone can pair from its
// Bluetooth settings. Either way the phone hands over its IRK, which iOS's Bluetooth
// daemon stores in the keychain ("apple" access group, service "MobileBluetooth"; needs
// the keychain-access-groups entitlement, so a jailbroken device). New or changed items
// there are the newly paired phone.
//
// What it finds is written to /var/mobile/Library/Logs/Jeeves-pairing.log (item layout
// only, never key values).
@interface JeevesPhonePairer : NSObject

@property (nonatomic, weak, nullable) id<JeevesPhonePairerDelegate> delegate;
@property (nonatomic, readonly) NSString *advertisedName;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
