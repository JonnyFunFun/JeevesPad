#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JeevesLovelaceItemKind) {
    JeevesLovelaceItemKindEntity,      // an entity card (tap/long-press like other Jeeves cards)
    JeevesLovelaceItemKindHeading,     // section/card title, full width
    JeevesLovelaceItemKindText,        // markdown card text, full width
    JeevesLovelaceItemKindUnsupported  // a card Jeeves can't draw natively (e.g. custom: cards)
};

// One thing to draw in a Jeeves grid, derived from a Lovelace card
@interface JeevesLovelaceItem : NSObject
@property (nonatomic, assign) JeevesLovelaceItemKind kind;
@property (nonatomic, copy, nullable) NSString *entityId;
@property (nonatomic, copy, nullable) NSString *name;  // card's name override, or heading/unsupported label
@property (nonatomic, copy, nullable) NSString *text;  // markdown text (template syntax is shown as-is)
@end

@interface JeevesLovelaceView : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<JeevesLovelaceItem *> *items;
@end

// A Lovelace dashboard config (from lovelace/config) translated into native items.
// Stacks and grids are flattened; entities/glance cards become a heading plus one
// entity card per row.
@interface JeevesLovelaceDashboard : NSObject

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy) NSArray<JeevesLovelaceView *> *views;

// Returns nil with an error for dashboards Jeeves can't translate (strategy-generated)
+ (nullable instancetype)dashboardFromConfig:(NSDictionary *)config error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
