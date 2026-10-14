#import "JeevesFleetCrypto.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonKeyDerivation.h>

static NSString * const kSalt = @"JeevesPad-fleet-v1";
static const uint kPBKDFRounds = 20000;
static const size_t kKeyLength = 32;

@interface JeevesFleetCrypto ()
@property (nonatomic, strong) NSData *encryptionKey;
@property (nonatomic, strong) NSData *macKey;
@end

@implementation JeevesFleetCrypto

- (instancetype)initWithFleetCode:(NSString *)fleetCode {
    self = [super init];
    if (self) {
        NSData *password = [fleetCode dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSData *salt = [kSalt dataUsingEncoding:NSUTF8StringEncoding];
        uint8_t derived[kKeyLength * 2];
        CCKeyDerivationPBKDF(kCCPBKDF2, password.bytes, password.length, salt.bytes, salt.length,
                             kCCPRFHmacAlgSHA256, kPBKDFRounds, derived, sizeof(derived));
        _encryptionKey = [NSData dataWithBytes:derived length:kKeyLength];
        _macKey = [NSData dataWithBytes:derived + kKeyLength length:kKeyLength];
    }
    return self;
}

- (NSData *)macForData:(NSData *)data {
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, self.macKey.bytes, self.macKey.length, data.bytes, data.length, mac);
    return [NSData dataWithBytes:mac length:sizeof(mac)];
}

- (NSData *)seal:(NSData *)plaintext {
    uint8_t iv[kCCBlockSizeAES128];
    arc4random_buf(iv, sizeof(iv));

    NSMutableData *ciphertext = [NSMutableData dataWithLength:plaintext.length + kCCBlockSizeAES128];
    size_t written = 0;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
            self.encryptionKey.bytes, self.encryptionKey.length, iv,
            plaintext.bytes, plaintext.length, ciphertext.mutableBytes, ciphertext.length, &written);
    ciphertext.length = written;

    NSMutableData *box = [NSMutableData dataWithBytes:iv length:sizeof(iv)];
    [box appendData:ciphertext];
    [box appendData:[self macForData:box]];
    return box;
}

- (NSData *)open:(NSData *)box {
    if (box.length < kCCBlockSizeAES128 * 2 + CC_SHA256_DIGEST_LENGTH) return nil;
    NSData *signedPart = [box subdataWithRange:NSMakeRange(0, box.length - CC_SHA256_DIGEST_LENGTH)];
    NSData *mac = [box subdataWithRange:NSMakeRange(signedPart.length, CC_SHA256_DIGEST_LENGTH)];

    // Constant-time comparison
    NSData *expected = [self macForData:signedPart];
    const uint8_t *a = mac.bytes, *b = expected.bytes;
    uint8_t diff = 0;
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) diff |= a[i] ^ b[i];
    if (diff != 0) return nil;

    const uint8_t *iv = signedPart.bytes;
    NSData *ciphertext = [signedPart subdataWithRange:NSMakeRange(kCCBlockSizeAES128, signedPart.length - kCCBlockSizeAES128)];
    NSMutableData *plaintext = [NSMutableData dataWithLength:ciphertext.length + kCCBlockSizeAES128];
    size_t written = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                     self.encryptionKey.bytes, self.encryptionKey.length, iv,
                                     ciphertext.bytes, ciphertext.length, plaintext.mutableBytes, plaintext.length, &written);
    if (status != kCCSuccess) return nil;
    plaintext.length = written;
    return plaintext;
}

@end
