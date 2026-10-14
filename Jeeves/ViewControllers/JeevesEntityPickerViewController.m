#import "JeevesEntityPickerViewController.h"
#import "HAEntity.h"
#import "JeevesThemeManager.h"

static NSString * const kCellID = @"EntityPickerCell";

@interface JeevesEntityPickerViewController () <UISearchBarDelegate>
@property (nonatomic, copy) NSArray<HAEntity *> *entities;
@property (nonatomic, copy) NSArray<HAEntity *> *filteredEntities;
@property (nonatomic, copy) NSArray<NSString *> *options;
@property (nonatomic, copy) NSString *selectedEntityId;
@property (nonatomic, assign) NSInteger selectedOption;
@property (nonatomic, copy) void (^completion)(NSString *entityId, NSInteger optionIndex);
@end

@implementation JeevesEntityPickerViewController

- (instancetype)initWithTitle:(NSString *)title
                     entities:(NSArray<HAEntity *> *)entities
                      options:(NSArray<NSString *> *)options
             selectedEntityId:(NSString *)selectedEntityId
               selectedOption:(NSInteger)selectedOption
                   completion:(void (^)(NSString *, NSInteger))completion {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = title;
        _entities = [entities sortedArrayUsingComparator:^NSComparisonResult(HAEntity *a, HAEntity *b) {
            return [a.friendlyName ?: a.entityId compare:b.friendlyName ?: b.entityId options:NSCaseInsensitiveSearch];
        }];
        _filteredEntities = _entities;
        _options = options ?: @[];
        _selectedEntityId = [selectedEntityId copy];
        _selectedOption = selectedOption;
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];

    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    searchBar.placeholder = @"Search";
    searchBar.barStyle = UIBarStyleBlack;
    searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    searchBar.delegate = self;
    self.tableView.tableHeaderView = searchBar;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    NSString *query = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (query.length == 0) {
        self.filteredEntities = self.entities;
    } else {
        NSMutableArray *matches = [NSMutableArray array];
        for (HAEntity *entity in self.entities) {
            if ([entity.friendlyName rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [entity.entityId rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:entity];
            }
        }
        self.filteredEntities = matches;
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2; // options, entities
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.options.count : self.filteredEntities.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellID];
        cell.backgroundColor = [theme cardBackgroundColor];
        cell.textLabel.textColor = [theme textColor];
        cell.detailTextLabel.textColor = [theme secondaryTextColor];
        cell.tintColor = [theme onColor];
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [theme secondaryBackgroundColor];
        cell.selectedBackgroundView = selected;
    }

    if (indexPath.section == 0) {
        cell.textLabel.text = self.options[indexPath.row];
        cell.detailTextLabel.text = nil;
        cell.accessoryType = (!self.selectedEntityId && indexPath.row == self.selectedOption)
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        HAEntity *entity = self.filteredEntities[indexPath.row];
        NSString *unit = [entity.attributes[@"unit_of_measurement"] isKindOfClass:[NSString class]] ? entity.attributes[@"unit_of_measurement"] : @"";
        cell.textLabel.text = entity.friendlyName ?: entity.entityId;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@%@%@", entity.entityId, entity.state ?: @"",
                                     unit.length ? @" " : @"", unit];
        cell.accessoryType = [entity.entityId isEqualToString:self.selectedEntityId]
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        self.completion(nil, indexPath.row);
    } else {
        self.completion(self.filteredEntities[indexPath.row].entityId, -1);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end
