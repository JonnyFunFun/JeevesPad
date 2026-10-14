#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Authenticated encryption for fleet messages, keyed by the fleet code shared by
// all iPads: PBKDF2-SHA256 derives an AES-256-CBC key and an HMAC-SHA256 key, and
// boxes are IV || ciphertext || HMAC(IV || ciphertext) (encrypt-then-MAC).
@interface JeevesFleetCrypto : NSObject

- (instancetype)initWithFleetCode:(NSString *)fleetCode;

- (NSData *)seal:(NSData *)plaintext;
// nil if the box was made with a different fleet code or was tampered with
- (nullable NSData *)open:(NSData *)box;

@end

NS_ASSUME_NONNULL_END
