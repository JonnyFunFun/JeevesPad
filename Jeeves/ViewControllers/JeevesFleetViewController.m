#import "JeevesFleetViewController.h"
#import "JeevesFleetService.h"
#import "JeevesFleetSettings.h"
#import "JeevesThemeManager.h"

typedef NS_ENUM(NSInteger, FleetSection) {
    FleetSectionThisIPad,
    FleetSectionPeers,
    FleetSectionCount
};

static NSString * const kCellID = @"FleetCell";

@interface JeevesFleetViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *peerStatus; // last result per peer name
@property (nonatomic, assign) BOOL busy;
@end

@implementation JeevesFleetViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Fleet";
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.peerStatus = [NSMutableDictionary dictionary];

    JeevesFleetSettings *settings = [JeevesFleetSettings sharedSettings];
    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.onTintColor = [theme onColor];
    self.enabledSwitch.on = settings.enabled;
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged) forControlEvents:UIControlEventValueChanged];

    self.codeField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
    self.codeField.text = settings.fleetCode;
    self.codeField.textColor = [theme textColor];
    self.codeField.textAlignment = NSTextAlignmentRight;
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.codeField.returnKeyType = UIReturnKeyDone;
    self.codeField.delegate = self;
    self.codeField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Same on every iPad"
                                                                           attributes:@{NSForegroundColorAttributeName: [theme secondaryTextColor]}];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(peersChanged)
                                                 name:JeevesFleetPeersDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveCode];
}

- (void)peersChanged {
    [self.tableView reloadData];
}

#pragma mark - Configuration

- (void)enabledChanged {
    [self saveCode];
    [JeevesFleetSettings sharedSettings].enabled = self.enabledSwitch.on;
    [self.tableView reloadData];
}

- (void)saveCode {
    if (![self.codeField.text isEqualToString:[JeevesFleetSettings sharedSettings].fleetCode ?: @""]) {
        [JeevesFleetSettings sharedSettings].fleetCode = self.codeField.text;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self saveCode];
}

- (BOOL)isReady {
    JeevesFleetSettings *settings = [JeevesFleetSettings sharedSettings];
    return settings.enabled && settings.fleetCode.length > 0;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return FleetSectionCount;
}

- (NSArray<JeevesFleetPeer *> *)peers {
    return [JeevesFleetService sharedService].peers;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FleetSectionThisIPad) return 3; // sync switch, fleet code, name
    NSInteger peers = [self peers].count;
    return peers == 0 ? 1 : peers + 1; // "searching" placeholder, or peers + "send to all"
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == FleetSectionThisIPad ? @"This iPad" : @"iPads on This Network";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == FleetSectionThisIPad) {
        return @"iPads with fleet sync on and the same fleet code can share settings. Settings are encrypted with the "
               @"fleet code, which also stops other devices from changing or reading them.\n\n"
               @"Shared: Home Assistant connection, rooms, Home cards, card names and sizes, Home weather, idle "
               @"timeout and dimming, and the Jellyfin server.\n"
               @"Not shared: Jellyfin sign-in and playback target, wake on motion, and the battery webhook ID "
               @"(each iPad keeps its own).";
    }
    return @"Tap an iPad to send it this iPad's settings or copy its settings here. iPads appear while Jeeves is open on them.";
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
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.detailTextLabel.text = nil;

    if (indexPath.section == FleetSectionThisIPad) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"Fleet sync";
                cell.accessoryView = self.enabledSwitch;
                break;
            case 1:
                cell.textLabel.text = @"Fleet code";
                cell.accessoryView = self.codeField;
                break;
            default:
                cell.textLabel.text = @"Name";
                cell.detailTextLabel.text = [UIDevice currentDevice].name;
                break;
        }
        return cell;
    }

    NSArray<JeevesFleetPeer *> *peers = [self peers];
    if (peers.count == 0) {
        cell.textLabel.text = @"Searching for other iPads…";
        cell.textLabel.textColor = [theme secondaryTextColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row < (NSInteger)peers.count) {
        JeevesFleetPeer *peer = peers[indexPath.row];
        cell.textLabel.text = peer.name;
        cell.detailTextLabel.text = self.peerStatus[peer.name] ?: (peer.syncEnabled ? @"Fleet sync on" : @"Fleet sync off");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"Send My Settings to All iPads";
        cell.textLabel.textColor = [self isReady] ? [theme onColor] : [theme secondaryTextColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != FleetSectionPeers || self.busy) return;
    NSArray<JeevesFleetPeer *> *peers = [self peers];
    if (peers.count == 0) return;

    [self saveCode];
    if (![self isReady]) {
        [self showMessage:@"Turn on fleet sync and set the fleet code first." title:@"Fleet Sync Is Off"];
        return;
    }
    if (indexPath.row < (NSInteger)peers.count) {
        [self showActionsForPeer:peers[indexPath.row] sourceRect:[tableView rectForRowAtIndexPath:indexPath]];
    } else {
        [self pushToAll];
    }
}

#pragma mark - Actions

- (void)showActionsForPeer:(JeevesFleetPeer *)peer sourceRect:(CGRect)rect {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:peer.name message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Send My Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pushToPeer:peer];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Its Settings Here" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self confirmPullFromPeer:peer];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = rect;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setStatus:(NSString *)status forPeer:(JeevesFleetPeer *)peer {
    self.peerStatus[peer.name] = status;
    [self.tableView reloadData];
}

- (void)pushToPeer:(JeevesFleetPeer *)peer {
    self.busy = YES;
    [self setStatus:@"Sending…" forPeer:peer];
    [[JeevesFleetService sharedService] pushSettingsToPeer:peer completion:^(BOOL success, NSString *error) {
        self.busy = NO;
        [self setStatus:(success ? @"Settings sent" : @"Failed") forPeer:peer];
        if (!success) [self showMessage:error title:@"Couldn't Send Settings"];
    }];
}

- (void)pushToAll {
    NSArray<JeevesFleetPeer *> *peers = [self peers];
    __block NSInteger remaining = peers.count;
    NSMutableArray *failures = [NSMutableArray array];
    self.busy = YES;
    for (JeevesFleetPeer *peer in peers) {
        [self setStatus:@"Sending…" forPeer:peer];
        [[JeevesFleetService sharedService] pushSettingsToPeer:peer completion:^(BOOL success, NSString *error) {
            [self setStatus:(success ? @"Settings sent" : @"Failed") forPeer:peer];
            if (!success) [failures addObject:error ?: peer.name];
            if (--remaining > 0) return;
            self.busy = NO;
            NSInteger sent = peers.count - failures.count;
            NSString *summary = [NSString stringWithFormat:@"Sent to %ld of %lu iPads.", (long)sent, (unsigned long)peers.count];
            if (failures.count > 0) summary = [summary stringByAppendingFormat:@"\n\n%@", [failures componentsJoinedByString:@"\n"]];
            [self showMessage:summary title:(failures.count ? @"Some iPads Failed" : @"Settings Sent")];
        }];
    }
}

- (void)confirmPullFromPeer:(JeevesFleetPeer *)peer {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Copy Settings from %@?", peer.name]
                                                                   message:@"This iPad's shared settings (Home Assistant connection, rooms, cards, weather and idle settings) will be replaced."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        self.busy = YES;
        [self setStatus:@"Copying…" forPeer:peer];
        [[JeevesFleetService sharedService] pullSettingsFromPeer:peer completion:^(BOOL success, NSString *error) {
            self.busy = NO;
            // On success the app reloads with the new settings (and this screen closes)
            if (!success) {
                [self setStatus:@"Failed" forPeer:peer];
                [self showMessage:error title:@"Couldn't Copy Settings"];
            }
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
