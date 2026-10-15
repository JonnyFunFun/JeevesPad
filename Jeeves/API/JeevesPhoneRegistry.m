#import "JeevesPhoneRegistry.h"
#import "HAAPIClient.h"
#import "HAWebSocketClient.h"

static NSString * const kDomain = @"private_ble_device";
static const NSInteger kDeviceLookupAttempts = 6; // HA creates the device shortly after the entry
static const NSTimeInterval kDeviceLookupInterval = 1.5;

@implementation JeevesRegisteredPhone
@end

@implementation JeevesPhoneRegistry

#pragma mark - Keys

+ (NSString *)normalizedIRKFromString:(NSString *)input {
    NSString *key = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([key.lowercaseString hasPrefix:@"irk:"]) key = [key substringFromIndex:4];

    NSData *bytes = nil;
    if ([key hasSuffix:@"="]) {
        // Base64 (a Mac's Keychain): Home Assistant reverses the byte order
        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:key options:0];
        if (decoded.length == 16) {
            NSMutableData *reversed = [NSMutableData dataWithLength:16];
            const uint8_t *src = decoded.bytes;
            uint8_t *dst = reversed.mutableBytes;
            for (NSUInteger i = 0; i < 16; i++) dst[i] = src[15 - i];
            bytes = reversed;
        }
    } else {
        NSMutableString *hex = [NSMutableString string];
        for (NSString *part in [key componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" :,-\t\n"]]) {
            [hex appendString:([part.lowercaseString hasPrefix:@"0x"] ? [part substringFromIndex:2] : part)];
        }
        NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
        if (hex.length == 32 && [hex rangeOfCharacterFromSet:nonHex].location == NSNotFound) {
            return hex.lowercaseString;
        }
    }
    if (!bytes) return nil;

    NSMutableString *hex = [NSMutableString stringWithCapacity:32];
    const uint8_t *b = bytes.bytes;
    for (NSUInteger i = 0; i < bytes.length; i++) [hex appendFormat:@"%02x", b[i]];
    return hex;
}

#pragma mark - Errors

+ (NSString *)messageForStatus:(NSInteger)status json:(id)json error:(NSError *)error {
    if (error || status == 0) return error.localizedDescription ?: @"Couldn't reach Home Assistant.";
    if (status == 401) {
        return @"Home Assistant refused the request. Registering phones needs an access token from an "
               @"administrator account (Settings → Home Assistant).";
    }
    NSString *detail = [json isKindOfClass:[NSDictionary class]] ? json[@"message"] : nil;
    return [NSString stringWithFormat:@"Home Assistant returned an error (%ld%@).", (long)status,
            detail.length ? [@": " stringByAppendingString:detail] : @""];
}

#pragma mark - Listing

+ (void)fetchPhonesWithCompletion:(void (^)(NSArray<JeevesRegisteredPhone *> *, NSString *))completion {
    NSString *path = [NSString stringWithFormat:@"/api/config/config_entries/entry?domain=%@", kDomain];
    [[HAAPIClient sharedClient] sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSInteger status, id json, NSError *error) {
        if (status != 200 || ![json isKindOfClass:[NSArray class]]) {
            completion(nil, [self messageForStatus:status json:json error:error]);
            return;
        }
        NSMutableArray<JeevesRegisteredPhone *> *phones = [NSMutableArray array];
        for (NSDictionary *entry in json) {
            if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"entry_id"] isKindOfClass:[NSString class]]) continue;
            JeevesRegisteredPhone *phone = [[JeevesRegisteredPhone alloc] init];
            phone.entryId = entry[@"entry_id"];
            phone.irk = [entry[@"unique_id"] isKindOfClass:[NSString class]] ? entry[@"unique_id"] : @"";
            phone.name = [entry[@"title"] isKindOfClass:[NSString class]] ? entry[@"title"] : @"Phone";
            [phones addObject:phone];
        }
        if (phones.count == 0) {
            completion(phones, nil);
            return;
        }
        // Prefer the device's name (what Bermuda shows); the list still works without it
        [self fetchDevicesWithCompletion:^(NSArray *devices) {
            for (JeevesRegisteredPhone *phone in phones) {
                NSDictionary *device = [self deviceForIRK:phone.irk inDevices:devices];
                if (!device) continue;
                phone.deviceId = device[@"id"];
                NSString *name = device[@"name_by_user"];
                if ([name isKindOfClass:[NSString class]] && name.length) phone.name = name;
            }
            completion(phones, nil);
        }];
    }];
}

+ (void)fetchDevicesWithCompletion:(void (^)(NSArray *devices))completion {
    [HAWebSocketClient sendCommand:@{@"type": @"config/device_registry/list"} completion:^(id result, NSError *error) {
        completion([result isKindOfClass:[NSArray class]] ? result : @[]);
    }];
}

+ (NSDictionary *)deviceForIRK:(NSString *)irk inDevices:(NSArray *)devices {
    if (irk.length == 0) return nil;
    for (NSDictionary *device in devices) {
        if (![device isKindOfClass:[NSDictionary class]] || ![device[@"identifiers"] isKindOfClass:[NSArray class]]) continue;
        for (NSArray *identifier in device[@"identifiers"]) {
            if ([identifier isKindOfClass:[NSArray class]] && identifier.count == 2 &&
                [identifier[0] isEqual:kDomain] && [identifier[1] isEqual:irk]) {
                return device;
            }
        }
    }
    return nil;
}

#pragma mark - Registering

+ (void)registerPhoneWithKey:(NSString *)key name:(NSString *)name
                  completion:(void (^)(JeevesRegisteredPhone *, NSString *))completion {
    NSString *irk = [self normalizedIRKFromString:key];
    if (!irk) {
        completion(nil, @"That doesn't look like a phone's key. It should be 32 hexadecimal characters "
                        @"(an \"irk:\" prefix is fine) or 24 base64 characters ending in \"=\".");
        return;
    }
    [self registerPhoneWithCandidateKeys:@[irk] name:name completion:completion];
}

+ (void)registerPhoneWithCandidateKeys:(NSArray<NSString *> *)irks name:(NSString *)name
                            completion:(void (^)(JeevesRegisteredPhone *, NSString *))completion {
    [self fetchPhonesWithCompletion:^(NSArray<JeevesRegisteredPhone *> *phones, NSString *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        for (JeevesRegisteredPhone *phone in phones) {
            if ([irks containsObject:phone.irk]) {
                completion(nil, [NSString stringWithFormat:@"This phone is already registered as \u201c%@\u201d.", phone.name]);
                return;
            }
        }
        [self tryKeys:irks index:0 name:name completion:completion];
    }];
}

// Submits each key in turn until Home Assistant finds a phone with one of them
+ (void)tryKeys:(NSArray<NSString *> *)irks index:(NSUInteger)index name:(NSString *)name
     completion:(void (^)(JeevesRegisteredPhone *, NSString *))completion {
    NSString *irk = irks[index];
    [self submitIRK:irk completion:^(NSString *entryId, NSString *error, BOOL notFound) {
        if (notFound && index + 1 < irks.count) {
            [self tryKeys:irks index:index + 1 name:name completion:completion];
            return;
        }
        if (!entryId) {
            completion(nil, error);
            return;
        }
        JeevesRegisteredPhone *phone = [[JeevesRegisteredPhone alloc] init];
        phone.entryId = entryId;
        phone.irk = irk;
        phone.name = name;
        [self applyName:name toPhone:phone attemptsLeft:kDeviceLookupAttempts completion:^{
            completion(phone, nil);
        }];
    }];
}

// Runs Private BLE Device's config flow with one key. `notFound` = Home Assistant
// can't see a phone using it (wrong key, or the phone isn't near a proxy).
+ (void)submitIRK:(NSString *)irk completion:(void (^)(NSString *entryId, NSString *error, BOOL notFound))completion {
    HAAPIClient *client = [HAAPIClient sharedClient];
    [client sendRequestWithMethod:@"POST" path:@"/api/config/config_entries/flow"
                             body:@{@"handler": kDomain, @"show_advanced_options": @NO}
                       completion:^(NSInteger status, id json, NSError *error) {
        NSDictionary *result = [json isKindOfClass:[NSDictionary class]] ? json : nil;
        if (status != 200 || !result) {
            completion(nil, [self messageForStatus:status json:json error:error], NO);
            return;
        }
        if ([result[@"type"] isEqual:@"abort"]) {
            completion(nil, [self messageForAbortReason:result[@"reason"]], NO);
            return;
        }
        NSString *flowId = result[@"flow_id"];
        if (![flowId isKindOfClass:[NSString class]]) {
            completion(nil, @"Home Assistant returned an unexpected response.", NO);
            return;
        }

        NSString *flowPath = [@"/api/config/config_entries/flow/" stringByAppendingString:flowId];
        [client sendRequestWithMethod:@"POST" path:flowPath body:@{@"irk": irk} completion:^(NSInteger status2, id json2, NSError *error2) {
            NSDictionary *step = [json2 isKindOfClass:[NSDictionary class]] ? json2 : nil;
            if (status2 == 200 && [step[@"type"] isEqual:@"create_entry"]) {
                NSDictionary *entry = [step[@"result"] isKindOfClass:[NSDictionary class]] ? step[@"result"] : nil;
                completion([entry[@"entry_id"] isKindOfClass:[NSString class]] ? entry[@"entry_id"] : @"", nil, NO);
                return;
            }

            // Still on the form (the key was rejected) or failed: don't leave the flow open
            [client sendRequestWithMethod:@"DELETE" path:flowPath body:nil completion:^(NSInteger s, id j, NSError *e) {}];
            if (status2 == 200 && [step[@"type"] isEqual:@"abort"]) {
                completion(nil, [self messageForAbortReason:step[@"reason"]], NO);
            } else if (status2 == 200 && [step[@"errors"] isKindOfClass:[NSDictionary class]]) {
                NSString *code = step[@"errors"][@"irk"] ?: [[step[@"errors"] allValues] firstObject];
                completion(nil, [self messageForFormError:code], [code isEqual:@"irk_not_found"]);
            } else {
                completion(nil, [self messageForStatus:status2 json:json2 error:error2], NO);
            }
        }];
    }];
}

+ (NSString *)messageForAbortReason:(NSString *)reason {
    if ([reason isEqual:@"bluetooth_not_available"]) {
        return @"Home Assistant has no Bluetooth adapter or Bluetooth proxy set up, so it can't track phones yet.";
    }
    if ([reason isEqual:@"already_configured"]) {
        return @"This phone is already registered.";
    }
    return [NSString stringWithFormat:@"Home Assistant stopped the registration (%@).", reason ?: @"unknown reason"];
}

+ (NSString *)messageForFormError:(NSString *)code {
    if ([code isEqual:@"irk_not_found"]) {
        return @"Home Assistant can't see this phone right now. Unlock the phone, keep it near one of your "
               @"Bluetooth proxies for a moment, and try again. If it still isn't found, check the key.";
    }
    if ([code isEqual:@"irk_not_valid"]) {
        return @"Home Assistant says this isn't a valid key.";
    }
    return [NSString stringWithFormat:@"Home Assistant rejected the key (%@).", code ?: @"unknown error"];
}

#pragma mark - Naming

// Names the config entry and the device (Bermuda uses the device's name). The device
// appears a moment after the entry is created, so look for it a few times.
+ (void)applyName:(NSString *)name toPhone:(JeevesRegisteredPhone *)phone attemptsLeft:(NSInteger)attempts completion:(void (^)(void))completion {
    if (attempts == kDeviceLookupAttempts && phone.entryId.length) {
        [HAWebSocketClient sendCommand:@{@"type": @"config_entries/update", @"entry_id": phone.entryId, @"title": name}
                            completion:^(id result, NSError *error) {
            if (error) NSLog(@"[Jeeves] Couldn't rename config entry: %@", error.localizedDescription);
        }];
    }
    void (^renameDevice)(void) = ^{
        [HAWebSocketClient sendCommand:@{@"type": @"config/device_registry/update", @"device_id": phone.deviceId, @"name_by_user": name}
                            completion:^(id result, NSError *error) {
            if (error) NSLog(@"[Jeeves] Couldn't rename device: %@", error.localizedDescription);
            completion();
        }];
    };
    if (phone.deviceId) {
        renameDevice();
        return;
    }
    [self fetchDevicesWithCompletion:^(NSArray *devices) {
        NSDictionary *device = [self deviceForIRK:phone.irk inDevices:devices];
        if ([device[@"id"] isKindOfClass:[NSString class]]) {
            phone.deviceId = device[@"id"];
            renameDevice();
        } else if (attempts > 1) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDeviceLookupInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self applyName:name toPhone:phone attemptsLeft:attempts - 1 completion:completion];
            });
        } else {
            NSLog(@"[Jeeves] Private BLE device for %@ not found; it keeps Home Assistant's default name", phone.entryId);
            completion();
        }
    }];
}

+ (void)renamePhone:(JeevesRegisteredPhone *)phone to:(NSString *)name completion:(void (^)(NSString *))completion {
    [HAWebSocketClient sendCommand:@{@"type": @"config_entries/update", @"entry_id": phone.entryId, @"title": name}
                        completion:^(id result, NSError *error) {
        if (error) {
            completion(error.localizedDescription);
            return;
        }
        phone.name = name;
        [self applyName:name toPhone:phone attemptsLeft:1 completion:^{
            completion(nil);
        }];
    }];
}

+ (void)removePhone:(JeevesRegisteredPhone *)phone completion:(void (^)(NSString *))completion {
    NSString *path = [@"/api/config/config_entries/entry/" stringByAppendingString:phone.entryId];
    [[HAAPIClient sharedClient] sendRequestWithMethod:@"DELETE" path:path body:nil completion:^(NSInteger status, id json, NSError *error) {
        completion(status == 200 ? nil : [self messageForStatus:status json:json error:error]);
    }];
}

@end
