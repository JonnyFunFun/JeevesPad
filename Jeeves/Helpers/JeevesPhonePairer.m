#import "JeevesPhonePairer.h"
#import "JeevesIdleManager.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <Security/Security.h>

static NSString * const kKeychainAccessGroup = @"apple";
static NSString * const kKeychainService = @"MobileBluetooth";
static NSString * const kServiceUUID = @"6E4A0001-1B2C-4D5E-8F90-4A6B7C8D9E01";
static NSString * const kCharacteristicUUID = @"6E4A0002-1B2C-4D5E-8F90-4A6B7C8D9E01";
static NSString * const kLogPath = @"/var/mobile/Library/Logs/Jeeves-pairing.log";

static const NSTimeInterval kPollInterval = 2.0;
static const NSTimeInterval kSettleTime = 3.0;     // bluetoothd may write a new pairing in steps
static const NSTimeInterval kGiveUpAfterChange = 15.0;
static const NSTimeInterval kTimeout = 300.0;
static const NSUInteger kMaxKeys = 12;

@interface JeevesPhonePairer () <CBPeripheralManagerDelegate>
@property (nonatomic, strong) CBPeripheralManager *manager;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) NSDictionary<NSString *, NSDate *> *baseline; // account → modification date
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong) NSDate *firstChangeTime;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSMutableString *log;
@end

@implementation JeevesPhonePairer

- (NSString *)advertisedName {
    return @"Jeeves Pairing";
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Lifecycle

- (void)start {
    if (self.running) return;
    self.running = YES;
    self.log = [NSMutableString stringWithFormat:@"Jeeves pairing %@\n", [NSDate date]];
    self.firstChangeTime = nil;
    self.startTime = [NSDate date];

    OSStatus status = noErr;
    NSArray<NSDictionary *> *items = [self keychainItemsWithStatus:&status];
    [self.log appendFormat:@"Keychain query: status %d, %lu existing item(s)\n", (int)status, (unsigned long)items.count];
    if (!items) {
        [self failWithError:[NSString stringWithFormat:@"Jeeves can't read this iPad's Bluetooth keys (keychain error %d). "
                                                       @"It needs to be installed with deploy.sh or deploy_fleet.sh, which give it permission.", (int)status]];
        return;
    }
    self.baseline = [self modificationDatesForItems:items];

    self.manager = [[CBPeripheralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()
                                                         options:@{CBPeripheralManagerOptionShowPowerAlertKey: @YES}];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval target:self selector:@selector(poll)
                                                    userInfo:nil repeats:YES];
}

- (void)stop {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    if (self.manager) {
        self.manager.delegate = nil;
        if (self.manager.isAdvertising) [self.manager stopAdvertising];
        [self.manager removeAllServices];
        self.manager = nil;
    }
    if (self.running && self.log.length) {
        [self.log writeToFile:kLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    self.running = NO;
}

- (void)failWithError:(NSString *)error {
    [self.log appendFormat:@"Failed: %@\n", error];
    [self stop];
    [self.delegate phonePairer:self didFailWithError:error];
}

#pragma mark - Peripheral

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    switch (peripheral.state) {
        case CBPeripheralManagerStatePoweredOn: {
            CBMutableCharacteristic *characteristic =
                [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:kCharacteristicUUID]
                                                   properties:CBCharacteristicPropertyRead
                                                        value:nil
                                                  permissions:CBAttributePermissionsReadEncryptionRequired];
            CBMutableService *service = [[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:kServiceUUID] primary:YES];
            service.characteristics = @[characteristic];
            [peripheral removeAllServices];
            [peripheral addService:service];
            break;
        }
        case CBPeripheralManagerStatePoweredOff:
            [self failWithError:@"Bluetooth is turned off on this iPad. Turn it on in Settings or Control Center, then try again."];
            break;
        case CBPeripheralManagerStateUnauthorized:
            [self failWithError:@"Jeeves isn't allowed to use Bluetooth. Allow it in Settings → Privacy → Bluetooth Sharing."];
            break;
        case CBPeripheralManagerStateUnsupported:
            [self failWithError:@"This iPad can't act as a Bluetooth accessory."];
            break;
        default:
            break; // resetting / unknown: wait for the next update
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(CBService *)service error:(NSError *)error {
    if (error) {
        [self failWithError:[NSString stringWithFormat:@"Couldn't start Bluetooth pairing (%@).", error.localizedDescription]];
        return;
    }
    [peripheral startAdvertising:@{CBAdvertisementDataLocalNameKey: self.advertisedName,
                                   CBAdvertisementDataServiceUUIDsKey: @[[CBUUID UUIDWithString:kServiceUUID]]}];
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    if (error) {
        [self failWithError:[NSString stringWithFormat:@"Couldn't start Bluetooth pairing (%@).", error.localizedDescription]];
        return;
    }
    [self.log appendString:@"Advertising\n"];
    [self.delegate phonePairerIsWaitingForPhone:self];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request {
    // Only reachable over an encrypted (so paired) link
    NSData *value = [@"Jeeves" dataUsingEncoding:NSUTF8StringEncoding];
    if (request.offset > value.length) {
        [peripheral respondToRequest:request withResult:CBATTErrorInvalidOffset];
        return;
    }
    request.value = [value subdataWithRange:NSMakeRange(request.offset, value.length - request.offset)];
    [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
    [self.log appendFormat:@"Encrypted read from %@\n", request.central.identifier.UUIDString];
    [self poll];
}

#pragma mark - Keychain

// nil if the keychain couldn't be read; empty if there are no pairings
- (NSArray<NSDictionary *> *)keychainItemsWithStatus:(OSStatus *)outStatus {
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrAccessGroup: kKeychainAccessGroup,
                            (__bridge id)kSecAttrService: kKeychainService,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                            (__bridge id)kSecReturnAttributes: @YES};
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (outStatus) *outStatus = status;
    if (status == errSecItemNotFound) return @[];
    if (status != errSecSuccess) return nil;
    id items = CFBridgingRelease(result);
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

- (NSData *)dataForItem:(NSDictionary *)item {
    id account = item[(__bridge id)kSecAttrAccount];
    if (!account) return nil;
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrAccessGroup: kKeychainAccessGroup,
                            (__bridge id)kSecAttrService: kKeychainService,
                            (__bridge id)kSecAttrAccount: account,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
                            (__bridge id)kSecReturnData: @YES};
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        [self.log appendFormat:@"  data: error %d\n", (int)status];
        return nil;
    }
    id data = CFBridgingRelease(result);
    return [data isKindOfClass:[NSData class]] ? data : nil;
}

- (NSString *)accountOfItem:(NSDictionary *)item {
    id account = item[(__bridge id)kSecAttrAccount];
    if ([account isKindOfClass:[NSData class]]) {
        NSString *string = [[NSString alloc] initWithData:account encoding:NSUTF8StringEncoding];
        return string ?: [account description];
    }
    return [account description] ?: @"";
}

- (NSDictionary<NSString *, NSDate *> *)modificationDatesForItems:(NSArray<NSDictionary *> *)items {
    NSMutableDictionary *dates = [NSMutableDictionary dictionary];
    for (NSDictionary *item in items) {
        dates[[self accountOfItem:item]] = item[(__bridge id)kSecAttrModificationDate] ?: [NSDate distantPast];
    }
    return dates;
}

#pragma mark - Watching for the new pairing

- (void)poll {
    if (!self.running) return;
    [[JeevesIdleManager sharedManager] userDidInteract]; // the user is busy with their phone: don't go Home

    if ([[NSDate date] timeIntervalSinceDate:self.startTime] > kTimeout) {
        [self failWithError:@"No phone paired in 5 minutes. Tap Start to try again."];
        return;
    }

    NSArray<NSDictionary *> *items = [self keychainItemsWithStatus:NULL] ?: @[];
    NSMutableArray<NSDictionary *> *changed = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSDate *before = self.baseline[[self accountOfItem:item]];
        NSDate *now = item[(__bridge id)kSecAttrModificationDate] ?: [NSDate distantPast];
        if (!before || ![before isEqualToDate:now]) [changed addObject:item];
    }
    if (changed.count == 0) return;

    if (!self.firstChangeTime) {
        self.firstChangeTime = [NSDate date];
        [self.log appendFormat:@"%lu new or changed item(s)\n", (unsigned long)changed.count];
    }
    NSTimeInterval sinceChange = [[NSDate date] timeIntervalSinceDate:self.firstChangeTime];
    if (sinceChange < kSettleTime) return;

    NSArray<NSString *> *keys = [self keysFromItems:changed];
    if (keys.count > 0) {
        [self.log appendFormat:@"%lu possible key(s)\n", (unsigned long)keys.count];
        [self stop];
        [self.delegate phonePairer:self didPairWithKeys:keys];
    } else if (sinceChange > kGiveUpAfterChange) {
        [self failWithError:@"The phone paired, but Jeeves couldn't find its key. Please send the developer "
                            @"/var/mobile/Library/Logs/Jeeves-pairing.log, and add the phone with its key instead."];
    }
}

// Possible IRKs in the changed items: 16-byte values, those named like an IRK first,
// each in both byte orders (Home Assistant says which one it can see).
- (NSArray<NSString *> *)keysFromItems:(NSArray<NSDictionary *> *)items {
    NSMutableArray<NSData *> *named = [NSMutableArray array];
    NSMutableArray<NSData *> *others = [NSMutableArray array];
    for (NSDictionary *item in items) {
        [self.log appendFormat:@"Item %@:\n", [self accountOfItem:item]];
        for (id key in item) {
            id value = item[key];
            [self.log appendFormat:@"  attr %@: %@\n", key,
             ([value isKindOfClass:[NSData class]] ? [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)[value length]] : value)];
        }
        NSData *data = [self dataForItem:item];
        if (!data) continue;
        id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
        if (plist) {
            [self collectKeysIn:plist path:@"data" named:named others:others];
        } else {
            [self.log appendFormat:@"  data: <%lu bytes, not a property list>\n", (unsigned long)data.length];
            if (data.length == 16) [others addObject:data];
        }
    }

    NSMutableOrderedSet<NSString *> *keys = [NSMutableOrderedSet orderedSet];
    for (NSData *data in [named arrayByAddingObjectsFromArray:others]) {
        [keys addObject:[self hexForData:data reversed:NO]];
        [keys addObject:[self hexForData:data reversed:YES]];
    }
    NSArray *all = keys.array;
    return all.count > kMaxKeys ? [all subarrayWithRange:NSMakeRange(0, kMaxKeys)] : all;
}

- (void)collectKeysIn:(id)object path:(NSString *)path named:(NSMutableArray *)named others:(NSMutableArray *)others {
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (id key in object) {
            [self collectKeysIn:object[key] path:[NSString stringWithFormat:@"%@.%@", path, key] named:named others:others];
        }
        return;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        [object enumerateObjectsUsingBlock:^(id element, NSUInteger i, BOOL *stop) {
            [self collectKeysIn:element path:[NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)i] named:named others:others];
        }];
        return;
    }

    NSData *data = nil;
    if ([object isKindOfClass:[NSData class]]) {
        data = object;
        [self.log appendFormat:@"  %@: <%lu bytes>\n", path, (unsigned long)data.length];
    } else if ([object isKindOfClass:[NSString class]]) {
        [self.log appendFormat:@"  %@: string(%lu)\n", path, (unsigned long)[object length]];
        data = [self dataFromHexString:object];
    } else {
        [self.log appendFormat:@"  %@: %@\n", path, NSStringFromClass([object class])];
    }
    if (data.length != 16) return;

    NSString *lower = path.lowercaseString;
    BOOL looksLikeIRK = [lower rangeOfString:@"irk"].location != NSNotFound ||
                        [lower rangeOfString:@"identity"].location != NSNotFound;
    BOOL looksLocal = [lower rangeOfString:@"local"].location != NSNotFound;
    if (looksLikeIRK && !looksLocal) {
        [named addObject:data];
    } else {
        [others addObject:data];
    }
}

- (NSData *)dataFromHexString:(NSString *)string {
    if (string.length != 32) return nil;
    NSMutableData *data = [NSMutableData dataWithCapacity:16];
    for (NSUInteger i = 0; i < 32; i += 2) {
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[string substringWithRange:NSMakeRange(i, 2)]];
        if (![scanner scanHexInt:&byte] || !scanner.isAtEnd) return nil;
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (NSString *)hexForData:(NSData *)data reversed:(BOOL)reversed {
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[reversed ? data.length - 1 - i : i]];
    }
    return hex;
}

@end
