#import "JeevesCardSettings.h"
#import "HAEntity.h"

NSString * const JeevesHomeDashboardID = @"home";
NSString * const JeevesCardSettingsDidChangeNotification = @"JeevesCardSettingsDidChangeNotification";

static NSString * const kDefaultsCardSettings = @"JeevesCardSettings";
static NSString * const kNameKey = @"name";
static NSString * const kSizeKey = @"size";

@interface JeevesCardSettings ()
// dashboardID -> entityId -> {name, size}
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *settings;
@end

@implementation JeevesCardSettings

+ (instancetype)sharedSettings {
    static JeevesCardSettings *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reloadFromDefaults];
    }
    return self;
}

- (void)reloadFromDefaults {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDefaultsCardSettings];
    for (NSString *dashboard in saved) {
        NSMutableDictionary *cards = [NSMutableDictionary dictionary];
        NSDictionary *savedCards = saved[dashboard];
        if (![savedCards isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *entityId in savedCards) {
            cards[entityId] = [savedCards[entityId] mutableCopy];
        }
        settings[dashboard] = cards;
    }
    _settings = settings;
}

- (void)saveAndNotifyDashboard:(NSString *)dashboardID {
    [[NSUserDefaults standardUserDefaults] setObject:self.settings forKey:kDefaultsCardSettings];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:JeevesCardSettingsDidChangeNotification object:dashboardID];
}

- (NSDictionary *)cardForEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    if (!entityId || !dashboardID) return nil;
    return self.settings[dashboardID][entityId];
}

- (NSMutableDictionary *)mutableCardForEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    NSMutableDictionary *cards = self.settings[dashboardID];
    if (!cards) {
        cards = [NSMutableDictionary dictionary];
        self.settings[dashboardID] = cards;
    }
    NSMutableDictionary *card = cards[entityId];
    if (!card) {
        card = [NSMutableDictionary dictionary];
        cards[entityId] = card;
    }
    return card;
}

// Drops cards (and dashboards) that no longer customize anything
- (void)pruneEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    NSMutableDictionary *cards = self.settings[dashboardID];
    if ([cards[entityId] count] == 0) [cards removeObjectForKey:entityId];
    if (cards.count == 0) [self.settings removeObjectForKey:dashboardID];
}

#pragma mark - Names

- (NSString *)customNameForEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    NSString *name = [self cardForEntityId:entityId dashboard:dashboardID][kNameKey];
    return name.length > 0 ? name : nil;
}

- (void)setCustomName:(NSString *)name forEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    if (!entityId || !dashboardID) return;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if ([trimmed isEqualToString:[self customNameForEntityId:entityId dashboard:dashboardID] ?: @""]) return;

    NSMutableDictionary *card = [self mutableCardForEntityId:entityId dashboard:dashboardID];
    if (trimmed.length > 0) {
        card[kNameKey] = trimmed;
    } else {
        [card removeObjectForKey:kNameKey];
    }
    [self pruneEntityId:entityId dashboard:dashboardID];
    [self saveAndNotifyDashboard:dashboardID];
}

- (NSString *)displayNameForEntity:(HAEntity *)entity dashboard:(NSString *)dashboardID {
    return [self customNameForEntityId:entity.entityId dashboard:dashboardID] ?: entity.friendlyName;
}

#pragma mark - Sizes

- (JeevesCardSize)sizeForEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    NSInteger size = [[self cardForEntityId:entityId dashboard:dashboardID][kSizeKey] integerValue];
    return (size >= JeevesCardSizeSmall && size <= JeevesCardSizeXSmall) ? (JeevesCardSize)size : JeevesCardSizeSmall;
}

- (void)setSize:(JeevesCardSize)size forEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID {
    if (!entityId || !dashboardID) return;
    if (size == [self sizeForEntityId:entityId dashboard:dashboardID]) return;

    NSMutableDictionary *card = [self mutableCardForEntityId:entityId dashboard:dashboardID];
    if (size == JeevesCardSizeSmall) {
        [card removeObjectForKey:kSizeKey];
    } else {
        card[kSizeKey] = @(size);
    }
    [self pruneEntityId:entityId dashboard:dashboardID];
    [self saveAndNotifyDashboard:dashboardID];
}

#pragma mark - Removal

- (void)removeEntityId:(NSString *)entityId fromDashboard:(NSString *)dashboardID {
    if (![self cardForEntityId:entityId dashboard:dashboardID]) return;
    [self.settings[dashboardID] removeObjectForKey:entityId];
    [self pruneEntityId:entityId dashboard:dashboardID];
    [self saveAndNotifyDashboard:dashboardID];
}

- (void)removeDashboard:(NSString *)dashboardID {
    if (!dashboardID || !self.settings[dashboardID]) return;
    [self.settings removeObjectForKey:dashboardID];
    [self saveAndNotifyDashboard:dashboardID];
}

#pragma mark - Grid

+ (NSInteger)columnSpanForSize:(JeevesCardSize)size {
    return (size == JeevesCardSizeWide || size == JeevesCardSizeLarge) ? 2 : 1;
}

+ (NSInteger)rowSpanForSize:(JeevesCardSize)size {
    switch (size) {
        case JeevesCardSizeXSmall: return 1;
        case JeevesCardSizeTall:
        case JeevesCardSizeLarge:  return 4;
        default:                   return 2;
    }
}

+ (NSArray<NSNumber *> *)orderedSizes {
    return @[@(JeevesCardSizeXSmall), @(JeevesCardSizeSmall), @(JeevesCardSizeWide),
             @(JeevesCardSizeTall), @(JeevesCardSizeLarge)];
}

+ (NSString *)titleForSize:(JeevesCardSize)size {
    switch (size) {
        case JeevesCardSizeXSmall: return @"X-Small";
        case JeevesCardSizeWide:   return @"Wide";
        case JeevesCardSizeTall:   return @"Tall";
        case JeevesCardSizeLarge:  return @"Large";
        default:                   return @"Small";
    }
}

+ (NSArray<NSValue *> *)packSpans:(NSArray<NSValue *> *)spans columns:(NSInteger)columns rowCount:(NSInteger *)rowCount {
    columns = MAX(1, columns);
    NSMutableArray<NSMutableArray<NSNumber *> *> *occupied = [NSMutableArray array]; // [row][column]
    NSMutableArray<NSValue *> *origins = [NSMutableArray array];
    NSInteger rowsUsed = 0;

    for (NSValue *spanValue in spans) {
        CGSize span = [spanValue CGSizeValue];
        NSInteger w = MIN(MAX(1, (NSInteger)span.width), columns);
        NSInteger h = MAX(1, (NSInteger)span.height);

        for (NSInteger row = 0; ; row++) {
            BOOL placed = NO;
            for (NSInteger col = 0; col + w <= columns; col++) {
                BOOL fits = YES;
                for (NSInteger r = row; r < row + h && fits; r++) {
                    for (NSInteger c = col; c < col + w && fits; c++) {
                        if (r < (NSInteger)occupied.count && [occupied[r][c] boolValue]) fits = NO;
                    }
                }
                if (!fits) continue;

                while ((NSInteger)occupied.count < row + h) {
                    NSMutableArray *newRow = [NSMutableArray array];
                    for (NSInteger c = 0; c < columns; c++) [newRow addObject:@NO];
                    [occupied addObject:newRow];
                }
                for (NSInteger r = row; r < row + h; r++) {
                    for (NSInteger c = col; c < col + w; c++) occupied[r][c] = @YES;
                }
                [origins addObject:[NSValue valueWithCGPoint:CGPointMake(col, row)]];
                rowsUsed = MAX(rowsUsed, row + h);
                placed = YES;
                break;
            }
            if (placed) break;
        }
    }
    if (rowCount) *rowCount = rowsUsed;
    return origins;
}

@end
