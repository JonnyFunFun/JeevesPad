#import <Foundation/Foundation.h>

@interface JeevesRoom : NSObject <NSCoding>

@property (nonatomic, strong) NSString *roomId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) NSInteger iconType; // JeevesIconType value
@property (nonatomic, strong) NSMutableArray<NSString *> *entityIds;
@property (nonatomic, assign) NSInteger sortOrder;

+ (instancetype)roomWithName:(NSString *)name iconType:(NSInteger)iconType;
- (void)addEntityId:(NSString *)entityId;
- (void)removeEntityId:(NSString *)entityId;

@end

// Room Storage Manager
@interface JeevesRoomManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSArray<JeevesRoom *> *rooms;

- (void)addRoom:(JeevesRoom *)room;
- (void)removeRoom:(JeevesRoom *)room;
- (void)updateRoom:(JeevesRoom *)room;
- (void)moveRoomFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
- (void)saveRooms;
- (JeevesRoom *)roomWithId:(NSString *)roomId;

@end
