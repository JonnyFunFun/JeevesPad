#import "JeevesWeatherSettingsViewController.h"
#import "JeevesWeatherSettings.h"
#import "JeevesEntityPickerViewController.h"
#import "HAAPIClient.h"
#import "HAEntity.h"
#import "JeevesThemeManager.h"

typedef NS_ENUM(NSInteger, WeatherSettingsSection) {
    WeatherSettingsSectionForecast,
    WeatherSettingsSectionTemperature,
    WeatherSettingsSectionReadings,
    WeatherSettingsSectionCount
};

static NSString * const kCellID = @"WeatherSettingsCell";

@interface JeevesWeatherSettingsViewController ()
@property (nonatomic, copy) NSArray<HAEntity *> *entities;
@end

@implementation JeevesWeatherSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Home Weather";
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];
    // Always editable so readings can be reordered and removed; other rows stay tappable
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;

    // Opened on its own (from Home) rather than pushed from Settings
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                              target:self
                                                                                              action:@selector(doneTapped)];
    }

    [[HAAPIClient sharedClient] fetchStatesWithCompletion:^(NSArray<HAEntity *> *entities, NSError *error) {
        self.entities = entities ?: @[];
        [self.tableView reloadData];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Entities

- (HAEntity *)entityWithId:(NSString *)entityId {
    for (HAEntity *entity in self.entities) {
        if ([entity.entityId isEqualToString:entityId]) return entity;
    }
    return nil;
}

- (NSArray<HAEntity *> *)entitiesWithPrefixes:(NSArray<NSString *> *)prefixes {
    NSMutableArray *matches = [NSMutableArray array];
    for (HAEntity *entity in self.entities) {
        for (NSString *prefix in prefixes) {
            if ([entity.entityId hasPrefix:prefix]) { [matches addObject:entity]; break; }
        }
    }
    return matches;
}

- (NSString *)describeEntityId:(NSString *)entityId {
    HAEntity *entity = [self entityWithId:entityId];
    if (entity) return entity.friendlyName ?: entityId;
    return self.entities ? [NSString stringWithFormat:@"%@ (not found)", entityId] : entityId;
}

- (NSString *)valueOfEntityId:(NSString *)entityId {
    HAEntity *entity = [self entityWithId:entityId];
    if (!entity) return nil;
    NSString *unit = [entity.attributes[@"unit_of_measurement"] isKindOfClass:[NSString class]] ? entity.attributes[@"unit_of_measurement"] : @"";
    return [NSString stringWithFormat:@"%@%@%@", entity.state ?: @"", unit.length ? @" " : @"", unit];
}

#pragma mark - Table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return WeatherSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == WeatherSettingsSectionReadings) {
        return [JeevesWeatherSettings sharedSettings].readingEntityIds.count + 1; // + "Add Reading"
    }
    return 1;
}

- (BOOL)isAddReadingRow:(NSIndexPath *)indexPath {
    return indexPath.section == WeatherSettingsSectionReadings &&
           indexPath.row == (NSInteger)[JeevesWeatherSettings sharedSettings].readingEntityIds.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case WeatherSettingsSectionForecast:    return @"Weather & Forecast";
        case WeatherSettingsSectionTemperature: return @"Temperature";
        default:                                return @"Readings";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case WeatherSettingsSectionForecast:
            return @"A weather entity provides the condition, icon and 6-day forecast. Choose None if you only use "
                   @"sensors, such as a personal weather station; the readings then fill the column.";
        case WeatherSettingsSectionTemperature:
            return @"The large temperature on the weather card. Use a sensor to show your own station's reading.";
        default:
            return @"Extra sensors shown on the weather card, e.g. humidity, wind, rain, pressure or UV. Drag to reorder. "
                   @"Tap a reading on the Home screen to see its details.";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kCellID];
        cell.backgroundColor = [theme cardBackgroundColor];
        cell.textLabel.textColor = [theme textColor];
        cell.detailTextLabel.textColor = [theme secondaryTextColor];
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [theme secondaryBackgroundColor];
        cell.selectedBackgroundView = selected;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [theme textColor];

    JeevesWeatherSettings *settings = [JeevesWeatherSettings sharedSettings];
    switch (indexPath.section) {
        case WeatherSettingsSectionForecast: {
            cell.textLabel.text = @"Weather entity";
            NSString *detail;
            if (settings.weatherSource == JeevesWeatherSourceNone) {
                detail = @"None";
            } else if (settings.weatherSource == JeevesWeatherSourceEntity) {
                detail = [self describeEntityId:settings.weatherEntityId];
            } else {
                HAEntity *automatic = [settings weatherEntityFromEntities:self.entities ?: @[]];
                detail = automatic ? [NSString stringWithFormat:@"Automatic (%@)", automatic.friendlyName] : @"Automatic";
            }
            cell.detailTextLabel.text = detail;
            cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case WeatherSettingsSectionTemperature:
            cell.textLabel.text = @"Temperature";
            cell.detailTextLabel.text = settings.temperatureEntityId
                ? [self describeEntityId:settings.temperatureEntityId] : @"From weather entity";
            cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        default:
            if ([self isAddReadingRow:indexPath]) {
                cell.textLabel.text = @"Add Reading…";
                cell.textLabel.textColor = [theme onColor];
                cell.detailTextLabel.text = nil;
            } else {
                NSString *entityId = settings.readingEntityIds[indexPath.row];
                cell.textLabel.text = [self describeEntityId:entityId];
                cell.detailTextLabel.text = [self valueOfEntityId:entityId];
            }
            break;
    }
    return cell;
}

#pragma mark - Editing (readings only)

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == WeatherSettingsSectionReadings;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != WeatherSettingsSectionReadings) return UITableViewCellEditingStyleNone;
    return [self isAddReadingRow:indexPath] ? UITableViewCellEditingStyleInsert : UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == WeatherSettingsSectionReadings;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleInsert) {
        [self pickReading];
    } else if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *ids = [[JeevesWeatherSettings sharedSettings].readingEntityIds mutableCopy];
        [ids removeObjectAtIndex:indexPath.row];
        [JeevesWeatherSettings sharedSettings].readingEntityIds = ids;
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == WeatherSettingsSectionReadings && ![self isAddReadingRow:indexPath];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
       toProposedIndexPath:(NSIndexPath *)proposed {
    // Keep readings within their section, above "Add Reading"
    NSInteger lastReading = (NSInteger)[JeevesWeatherSettings sharedSettings].readingEntityIds.count - 1;
    if (proposed.section < WeatherSettingsSectionReadings) return [NSIndexPath indexPathForRow:0 inSection:WeatherSettingsSectionReadings];
    if (proposed.section > WeatherSettingsSectionReadings || proposed.row > lastReading) {
        return [NSIndexPath indexPathForRow:lastReading inSection:WeatherSettingsSectionReadings];
    }
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSMutableArray *ids = [[JeevesWeatherSettings sharedSettings].readingEntityIds mutableCopy];
    NSString *moved = ids[source.row];
    [ids removeObjectAtIndex:source.row];
    [ids insertObject:moved atIndex:destination.row];
    [JeevesWeatherSettings sharedSettings].readingEntityIds = ids;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
        case WeatherSettingsSectionForecast:    [self pickWeatherEntity]; break;
        case WeatherSettingsSectionTemperature: [self pickTemperature]; break;
        default:
            if ([self isAddReadingRow:indexPath]) [self pickReading];
            break;
    }
}

- (void)pickWeatherEntity {
    JeevesWeatherSettings *settings = [JeevesWeatherSettings sharedSettings];
    NSInteger selectedOption = settings.weatherSource == JeevesWeatherSourceNone ? 1 : 0;
    NSString *selectedId = settings.weatherSource == JeevesWeatherSourceEntity ? settings.weatherEntityId : nil;
    JeevesEntityPickerViewController *picker =
        [[JeevesEntityPickerViewController alloc] initWithTitle:@"Weather Entity"
                                                       entities:[self entitiesWithPrefixes:@[@"weather."]]
                                                        options:@[@"Automatic", @"None"]
                                               selectedEntityId:selectedId
                                                 selectedOption:selectedOption
                                                     completion:^(NSString *entityId, NSInteger optionIndex) {
        if (entityId) {
            settings.weatherEntityId = entityId;
            settings.weatherSource = JeevesWeatherSourceEntity;
        } else {
            settings.weatherSource = (optionIndex == 1) ? JeevesWeatherSourceNone : JeevesWeatherSourceAutomatic;
        }
    }];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)pickTemperature {
    JeevesWeatherSettings *settings = [JeevesWeatherSettings sharedSettings];
    JeevesEntityPickerViewController *picker =
        [[JeevesEntityPickerViewController alloc] initWithTitle:@"Temperature"
                                                       entities:[self entitiesWithPrefixes:@[@"sensor."]]
                                                        options:@[@"From weather entity"]
                                               selectedEntityId:settings.temperatureEntityId
                                                 selectedOption:0
                                                     completion:^(NSString *entityId, NSInteger optionIndex) {
        settings.temperatureEntityId = entityId; // nil = from weather entity
    }];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)pickReading {
    JeevesWeatherSettings *settings = [JeevesWeatherSettings sharedSettings];
    JeevesEntityPickerViewController *picker =
        [[JeevesEntityPickerViewController alloc] initWithTitle:@"Add Reading"
                                                       entities:[self entitiesWithPrefixes:@[@"sensor.", @"binary_sensor."]]
                                                        options:nil
                                               selectedEntityId:nil
                                                 selectedOption:-1
                                                     completion:^(NSString *entityId, NSInteger optionIndex) {
        if (entityId && ![settings.readingEntityIds containsObject:entityId]) {
            settings.readingEntityIds = [settings.readingEntityIds arrayByAddingObject:entityId];
        }
    }];
    [self.navigationController pushViewController:picker animated:YES];
}

@end
