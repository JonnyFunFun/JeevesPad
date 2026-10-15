#import "JeevesPresenceViewController.h"
#import "JeevesAddPhoneViewController.h"
#import "JeevesPairPhoneViewController.h"
#import "JeevesPhoneRegistry.h"
#import "JeevesThemeManager.h"

typedef NS_ENUM(NSInteger, PresenceSection) {
    PresenceSectionPhones,
    PresenceSectionAdd,
    PresenceSectionCount
};

typedef NS_ENUM(NSInteger, PresenceAddRow) {
    PresenceAddRowPair,
    PresenceAddRowWithKey,
    PresenceAddRowAndroid,
    PresenceAddRowCount
};

static NSString * const kCellID = @"PresenceCell";

@interface JeevesPresenceViewController ()
@property (nonatomic, strong) NSArray<JeevesRegisteredPhone *> *phones; // nil while loading
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic, assign) BOOL busy;
@end

@implementation JeevesPresenceViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Presence";
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];
    [self reloadPhones];
}

- (void)reloadPhones {
    self.loadError = nil;
    [JeevesPhoneRegistry fetchPhonesWithCompletion:^(NSArray<JeevesRegisteredPhone *> *phones, NSString *error) {
        self.phones = [phones sortedArrayUsingComparator:^NSComparisonResult(JeevesRegisteredPhone *a, JeevesRegisteredPhone *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }] ?: @[];
        self.loadError = error;
        [self.tableView reloadData];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return PresenceSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == PresenceSectionAdd) return PresenceAddRowCount;
    return MAX((NSInteger)self.phones.count, 1); // phones, or a loading/empty/error row
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == PresenceSectionPhones ? @"Phones Tracked by Home Assistant" : @"Add a Phone";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == PresenceSectionPhones) {
        return @"These phones are registered with Home Assistant's Private BLE Device integration, and Bermuda tracks "
               @"them room by room. They're stored in Home Assistant, so every Jeeves panel shows the same list. "
               @"Tap a phone to rename or remove it.";
    }
    return @"iPhones (and Android phones that stay visible) are tracked by their Bluetooth key, which stays the same "
           @"while the phone's Bluetooth address keeps changing. Pairing the phone with this panel gets the key "
           @"automatically; if you already have the key, you can enter it instead. Many Android phones go quiet when "
           @"the screen is off, so the Home Assistant app's BLE Transmitter works better for them.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kCellID];
        cell.backgroundColor = [theme cardBackgroundColor];
        cell.detailTextLabel.textColor = [theme secondaryTextColor];
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [theme secondaryBackgroundColor];
        cell.selectedBackgroundView = selected;
    }
    cell.textLabel.textColor = [theme textColor];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == PresenceSectionAdd) {
        cell.textLabel.textColor = [theme accentColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        switch (indexPath.row) {
            case PresenceAddRowPair:    cell.textLabel.text = @"Pair a Phone with This Panel…"; break;
            case PresenceAddRowWithKey: cell.textLabel.text = @"Add a Phone with Its Bluetooth Key…"; break;
            default:                    cell.textLabel.text = @"Android: Use the Home Assistant App…"; break;
        }
        return cell;
    }

    if (self.phones.count == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [theme secondaryTextColor];
        cell.textLabel.numberOfLines = 0;
        if (!self.phones) {
            cell.textLabel.text = @"Loading…";
        } else if (self.loadError) {
            cell.textLabel.text = self.loadError;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault; // tap to retry
        } else {
            cell.textLabel.text = @"No phones registered yet";
        }
        return cell;
    }

    JeevesRegisteredPhone *phone = self.phones[indexPath.row];
    cell.textLabel.text = phone.name;
    if (phone.irk.length >= 6) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Key %@…", [phone.irk substringToIndex:6]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.busy) return;

    if (indexPath.section == PresenceSectionAdd) {
        __weak typeof(self) weakSelf = self;
        if (indexPath.row == PresenceAddRowPair) {
            JeevesPairPhoneViewController *pair = [[JeevesPairPhoneViewController alloc] init];
            pair.onRegistered = ^(JeevesRegisteredPhone *phone) {
                [weakSelf reloadPhones];
            };
            [self.navigationController pushViewController:pair animated:YES];
        } else if (indexPath.row == PresenceAddRowWithKey) {
            JeevesAddPhoneViewController *add = [[JeevesAddPhoneViewController alloc] init];
            add.onRegistered = ^(JeevesRegisteredPhone *phone) {
                [weakSelf reloadPhones];
            };
            [self.navigationController pushViewController:add animated:YES];
        } else {
            [self showAndroidInstructions];
        }
        return;
    }

    if (self.phones.count == 0) {
        if (self.loadError) {
            self.phones = nil;
            [self.tableView reloadData];
            [self reloadPhones];
        }
        return;
    }
    [self showActionsForPhone:self.phones[indexPath.row] sourceRect:[tableView rectForRowAtIndexPath:indexPath]];
}

#pragma mark - Actions

- (void)showAndroidInstructions {
    [self showMessage:@"1. Open the Home Assistant app on the phone.\n"
                      @"2. Go to Settings → Companion App → Manage Sensors.\n"
                      @"3. Turn on BLE Transmitter.\n"
                      @"4. In Home Assistant, open Bermuda's settings (Configure → Select Devices) and choose the "
                      @"phone's iBeacon.\n\n"
                      @"The phone then broadcasts its own beacon, even with the screen off, so it doesn't need to be "
                      @"registered here."
                title:@"Track an Android Phone"];
}

- (void)showActionsForPhone:(JeevesRegisteredPhone *)phone sourceRect:(CGRect)rect {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:phone.name message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptRenamePhone:phone];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Stop Tracking" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self confirmRemovePhone:phone];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = rect;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptRenamePhone:(JeevesRegisteredPhone *)phone {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Phone"
                                                                   message:@"This name is shown in Home Assistant and Bermuda."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = phone.name;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0 || [name isEqualToString:phone.name]) return;
        self.busy = YES;
        [JeevesPhoneRegistry renamePhone:phone to:name completion:^(NSString *error) {
            self.busy = NO;
            if (error) [self showMessage:error title:@"Couldn't Rename Phone"];
            [self reloadPhones];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRemovePhone:(JeevesRegisteredPhone *)phone {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Stop Tracking %@?", phone.name]
                                                                   message:@"The phone is removed from Home Assistant and Bermuda. You can add it again later with its key."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Stop Tracking" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        self.busy = YES;
        [JeevesPhoneRegistry removePhone:phone completion:^(NSString *error) {
            self.busy = NO;
            if (error) [self showMessage:error title:@"Couldn't Remove Phone"];
            [self reloadPhones];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!self.view.window || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
