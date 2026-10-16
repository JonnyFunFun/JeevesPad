#import "JeevesGuidedAccess.h"

NSString * const JeevesGuidedAccessDidChangeNotification = @"JeevesGuidedAccessDidChangeNotification";

static NSString * const kDefaultsWanted = @"JeevesGuidedAccessWanted"; // per iPad, not shared
static NSString * const kDefaultsCode   = @"JeevesGuidedAccessCode";   // shared with the fleet

@interface JeevesGuidedAccess ()
@property (nonatomic, copy, readwrite) NSString *lastError;
@end

@implementation JeevesGuidedAccess

+ (instancetype)sharedManager {
    static JeevesGuidedAccess *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (BOOL)isActive {
    return UIAccessibilityIsGuidedAccessEnabled();
}

- (BOOL)wanted {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsWanted];
}

- (NSString *)unlockCode {
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsCode];
    return code.length > 0 ? code : nil;
}

- (void)setUnlockCode:(NSString *)unlockCode {
    NSString *trimmed = [unlockCode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:kDefaultsCode];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsCode];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)checkUnlockCode:(NSString *)code {
    NSString *expected = self.unlockCode;
    return expected == nil || [code isEqualToString:expected];
}

- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged)
                                                 name:UIAccessibilityGuidedAccessStatusDidChangeNotification object:nil];
    if (self.wanted && !self.active) {
        [self request:YES completion:nil];
    }
}

- (void)statusChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesGuidedAccessDidChangeNotification object:self];
}

- (void)setWanted:(BOOL)wanted completion:(void (^)(BOOL))completion {
    [[NSUserDefaults standardUserDefaults] setBool:wanted forKey:kDefaultsWanted];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self request:wanted completion:completion];
}

- (void)request:(BOOL)enable completion:(void (^)(BOOL))completion {
    if (self.active == enable) {
        self.lastError = nil;
        if (completion) completion(YES);
        return;
    }
    UIAccessibilityRequestGuidedAccessSession(enable, ^(BOOL didSucceed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (didSucceed) {
                self.lastError = nil;
            } else if (enable) {
                self.lastError = @"iOS didn't let Jeeves start Guided Access. The iPad must be supervised, with "
                                 @"Jeeves allowed for Single App Mode in its configuration profile.";
            } else {
                self.lastError = @"iOS didn't let Jeeves end Guided Access.";
            }
            NSLog(@"[GuidedAccess] %@ %@", enable ? @"Start" : @"End", didSucceed ? @"succeeded" : @"failed");
            [self statusChanged];
            if (completion) completion(didSucceed);
        });
    });
}

@end
