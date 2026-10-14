#import "JeevesRoom.h"
#import "JeevesCardSettings.h"

@implementation JeevesRoom

+ (instancetype)roomWithName:(NSString *)name iconType:(NSInteger)iconType {
    JeevesRoom *room = [[JeevesRoom alloc] init];
    room.roomId = [[NSUUID UUID] UUIDString];
    room.name = name;
    room.iconType = iconType;
    room.entityIds = [NSMutableArray array];
    room.sortOrder = 0;
    return room;
}

- (void)addEntityId:(NSString *)entityId {
    if (![self.entityIds containsObject:entityId]) {
        [self.entityIds addObject:entityId];
    }
}

- (void)removeEntityId:(NSString *)entityId {
    [self.entityIds removeObject:entityId];
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.roomId forKey:@"roomId"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeInteger:self.iconType forKey:@"iconType"];
    [coder encodeObject:self.entityIds forKey:@"entityIds"];
    [coder encodeInteger:self.sortOrder forKey:@"sortOrder"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.roomId = [coder decodeObjectForKey:@"roomId"];
        self.name = [coder decodeObjectForKey:@"name"];
        self.iconType = [coder decodeIntegerForKey:@"iconType"];
        self.entityIds = [[coder decodeObjectForKey:@"entityIds"] mutableCopy];
        self.sortOrder = [coder decodeIntegerForKey:@"sortOrder"];

        if (!self.entityIds) {
            self.entityIds = [NSMutableArray array];
        }
    }
    return self;
}

@end

#pragma mark - JeevesRoomManager

@interface JeevesRoomManager ()
@property (nonatomic, strong) NSMutableArray<JeevesRoom *> *mutableRooms;
@end

@implementation JeevesRoomManager

+ (instancetype)sharedManager {
    static JeevesRoomManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadRooms];
    }
    return self;
}

- (NSArray<JeevesRoom *> *)rooms {
    return [self.mutableRooms copy];
}

- (void)reloadFromDefaults {
    [self loadRooms];
}

- (void)loadRooms {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"JeevesRooms"];
    if (data) {
        // Suppress deprecation warning - we need iOS 9.3.5 compatibility
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Rooms saved before the rename were archived under the old class name
        [NSKeyedUnarchiver setClass:[JeevesRoom class] forClassName:@"HBRoom"];
        NSArray *rooms = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        #pragma clang diagnostic pop
        self.mutableRooms = [rooms mutableCopy];
    } else {
        self.mutableRooms = [NSMutableArray array];
    }
}

- (void)saveRooms {
    // Suppress deprecation warning - we need iOS 9.3.5 compatibility
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.mutableRooms];
    #pragma clang diagnostic pop
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"JeevesRooms"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addRoom:(JeevesRoom *)room {
    room.sortOrder = self.mutableRooms.count;
    [self.mutableRooms addObject:room];
    [self saveRooms];
}

- (void)removeRoom:(JeevesRoom *)room {
    [[JeevesCardSettings sharedSettings] removeDashboard:room.roomId];
    [self.mutableRooms removeObject:room];
    [self saveRooms];
}

- (void)updateRoom:(JeevesRoom *)room {
    [self saveRooms];
}

- (void)moveRoomFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    if (fromIndex < 0 || fromIndex >= self.mutableRooms.count) return;
    if (toIndex < 0 || toIndex >= self.mutableRooms.count) return;

    JeevesRoom *room = self.mutableRooms[fromIndex];
    [self.mutableRooms removeObjectAtIndex:fromIndex];
    [self.mutableRooms insertObject:room atIndex:toIndex];

    for (NSInteger i = 0; i < self.mutableRooms.count; i++) {
        self.mutableRooms[i].sortOrder = i;
    }
    [self saveRooms];
}

- (JeevesRoom *)roomWithId:(NSString *)roomId {
    for (JeevesRoom *room in self.mutableRooms) {
        if ([room.roomId isEqualToString:roomId]) {
            return room;
        }
    }
    return nil;
}

@end
