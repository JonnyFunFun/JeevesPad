#import "JeevesLovelaceDashboard.h"

@implementation JeevesLovelaceItem

+ (instancetype)itemWithKind:(JeevesLovelaceItemKind)kind {
    JeevesLovelaceItem *item = [[self alloc] init];
    item.kind = kind;
    return item;
}

@end

@implementation JeevesLovelaceView
@end

static NSString *StringValue(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0 ? value : nil;
}

static NSArray *ArrayValue(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

@implementation JeevesLovelaceDashboard

+ (instancetype)dashboardFromConfig:(NSDictionary *)config error:(NSError **)error {
    if (config[@"strategy"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"JeevesLovelace" code:1 userInfo:@{NSLocalizedDescriptionKey:
                @"This dashboard is generated automatically by Home Assistant. To show it in Jeeves, "
                @"open it in Home Assistant and choose \"Take control\" (or pick another dashboard)."}];
        }
        return nil;
    }

    JeevesLovelaceDashboard *dashboard = [[self alloc] init];
    dashboard.title = StringValue(config[@"title"]);

    NSMutableArray *views = [NSMutableArray array];
    NSArray *viewConfigs = ArrayValue(config[@"views"]);
    for (NSUInteger i = 0; i < viewConfigs.count; i++) {
        NSDictionary *viewConfig = viewConfigs[i];
        if (![viewConfig isKindOfClass:[NSDictionary class]]) continue;
        if ([viewConfig[@"subview"] boolValue]) continue; // reached from other views, not tabs

        JeevesLovelaceView *view = [[JeevesLovelaceView alloc] init];
        view.title = StringValue(viewConfig[@"title"]) ?: StringValue(viewConfig[@"path"])
                     ?: [NSString stringWithFormat:@"View %lu", (unsigned long)(i + 1)];

        NSMutableArray *items = [NSMutableArray array];
        if (viewConfig[@"strategy"]) {
            JeevesLovelaceItem *note = [JeevesLovelaceItem itemWithKind:JeevesLovelaceItemKindText];
            note.text = @"This view is generated automatically by Home Assistant and can't be shown in Jeeves.";
            [items addObject:note];
        }
        for (NSDictionary *card in ArrayValue(viewConfig[@"cards"])) {
            [self addCard:card toItems:items];
        }
        // "Sections" views group cards into sections
        for (NSDictionary *section in ArrayValue(viewConfig[@"sections"])) {
            if (![section isKindOfClass:[NSDictionary class]]) continue;
            [self addHeading:StringValue(section[@"title"]) toItems:items];
            for (NSDictionary *card in ArrayValue(section[@"cards"])) {
                [self addCard:card toItems:items];
            }
        }
        view.items = items;
        [views addObject:view];
    }
    dashboard.views = views;
    return dashboard;
}

+ (void)addHeading:(NSString *)title toItems:(NSMutableArray *)items {
    if (title.length == 0) return;
    JeevesLovelaceItem *heading = [JeevesLovelaceItem itemWithKind:JeevesLovelaceItemKindHeading];
    heading.name = title;
    [items addObject:heading];
}

+ (void)addEntity:(NSString *)entityId name:(NSString *)name toItems:(NSMutableArray *)items {
    if (entityId.length == 0) return;
    JeevesLovelaceItem *item = [JeevesLovelaceItem itemWithKind:JeevesLovelaceItemKindEntity];
    item.entityId = entityId;
    item.name = name;
    [items addObject:item];
}

// Rows of an entities/glance card: entity ids, {entity, name} objects, or special rows
+ (void)addEntityRows:(NSArray *)rows toItems:(NSMutableArray *)items {
    for (id row in rows) {
        if ([row isKindOfClass:[NSString class]]) {
            [self addEntity:row name:nil toItems:items];
        } else if ([row isKindOfClass:[NSDictionary class]]) {
            if (StringValue(row[@"entity"])) {
                [self addEntity:row[@"entity"] name:StringValue(row[@"name"]) toItems:items];
            } else if ([row[@"type"] isEqual:@"section"]) {
                [self addHeading:StringValue(row[@"label"]) toItems:items];
            }
            // dividers, buttons, call-service and other special rows are skipped
        }
    }
}

+ (void)addCard:(NSDictionary *)card toItems:(NSMutableArray *)items {
    if (![card isKindOfClass:[NSDictionary class]]) return;
    NSString *type = StringValue(card[@"type"]) ?: @"";

    // Layout cards: keep their title, flatten their children
    if ([type isEqualToString:@"vertical-stack"] || [type isEqualToString:@"horizontal-stack"] || [type isEqualToString:@"grid"]) {
        [self addHeading:StringValue(card[@"title"]) toItems:items];
        for (NSDictionary *child in ArrayValue(card[@"cards"])) [self addCard:child toItems:items];
        return;
    }
    // Conditional cards are shown unconditionally (conditions aren't evaluated)
    if ([type isEqualToString:@"conditional"] || [type isEqualToString:@"entity-filter"]) {
        if ([card[@"card"] isKindOfClass:[NSDictionary class]] && ![type isEqualToString:@"entity-filter"]) {
            [self addCard:card[@"card"] toItems:items];
            return;
        }
    }
    if ([type isEqualToString:@"heading"]) {
        [self addHeading:StringValue(card[@"heading"]) toItems:items];
        return;
    }
    if ([type isEqualToString:@"markdown"]) {
        [self addHeading:StringValue(card[@"title"]) toItems:items];
        NSString *content = StringValue(card[@"content"]);
        if (content) {
            JeevesLovelaceItem *text = [JeevesLovelaceItem itemWithKind:JeevesLovelaceItemKindText];
            text.text = content;
            [items addObject:text];
        }
        return;
    }
    // Any card about a single entity (tile, button, light, entity, sensor, thermostat,
    // media-control, gauge, ...) becomes a Jeeves entity card
    if (StringValue(card[@"entity"])) {
        [self addEntity:card[@"entity"] name:StringValue(card[@"name"]) toItems:items];
        return;
    }
    // Cards listing entities (entities, glance, entity-filter, ...)
    if ([card[@"entities"] isKindOfClass:[NSArray class]]) {
        [self addHeading:StringValue(card[@"title"]) toItems:items];
        [self addEntityRows:card[@"entities"] toItems:items];
        return;
    }

    JeevesLovelaceItem *unsupported = [JeevesLovelaceItem itemWithKind:JeevesLovelaceItemKindUnsupported];
    unsupported.name = StringValue(card[@"title"]) ?: StringValue(card[@"name"]) ?: (type.length > 0 ? type : @"Card");
    unsupported.text = type;
    [items addObject:unsupported];
}

@end
