#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class HAEntity;

// Raw values are persisted, so new sizes must be appended rather than reordered.
// Use +orderedSizes for display order.
typedef NS_ENUM(NSInteger, JeevesCardSize) {
    JeevesCardSizeSmall = 0, // 1 column x 1 row (a square cell)
    JeevesCardSizeWide,      // 2 x 1
    JeevesCardSizeTall,      // 1 x 2
    JeevesCardSizeLarge,     // 2 x 2
    JeevesCardSizeXSmall     // 1 x half a row
};

// Dashboard ID of the Home screen; room dashboards use their roomId
extern NSString * const JeevesHomeDashboardID;
// Posted (object = dashboard ID) when a card's name or size changes
extern NSString * const JeevesCardSettingsDidChangeNotification;

// Per-card customizations: a display name and size for an entity on a specific
// dashboard. Stored locally; the entity in Home Assistant is not renamed.
@interface JeevesCardSettings : NSObject

+ (instancetype)sharedSettings;

- (NSString *)customNameForEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID; // nil if not renamed
- (void)setCustomName:(NSString *)name forEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID; // nil/empty clears
- (NSString *)displayNameForEntity:(HAEntity *)entity dashboard:(NSString *)dashboardID; // custom name or friendly name

- (JeevesCardSize)sizeForEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID;
- (void)setSize:(JeevesCardSize)size forEntityId:(NSString *)entityId dashboard:(NSString *)dashboardID;

- (void)removeEntityId:(NSString *)entityId fromDashboard:(NSString *)dashboardID;
- (void)removeDashboard:(NSString *)dashboardID;

// Re-reads settings from NSUserDefaults (e.g. after another iPad shared its settings)
- (void)reloadFromDefaults;

// Grid spans. Rows are half-height units so X-Small cards fit: a Small card is
// 1 column x 2 half-rows.
+ (NSInteger)columnSpanForSize:(JeevesCardSize)size;
+ (NSInteger)rowSpanForSize:(JeevesCardSize)size;
+ (NSArray<NSNumber *> *)orderedSizes; // smallest first, for pickers
+ (NSString *)titleForSize:(JeevesCardSize)size;

// Places cards with the given spans (CGSize width = columns, height = half-rows) into a
// grid with `columns` columns, first-fit in order. Returns each card's origin
// (x = column, y = row) as NSValue CGPoints; `rowCount` receives the rows used.
+ (NSArray<NSValue *> *)packSpans:(NSArray<NSValue *> *)spans columns:(NSInteger)columns rowCount:(NSInteger *)rowCount;

@end
