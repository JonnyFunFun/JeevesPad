#import "JeevesPairPhoneViewController.h"
#import "JeevesPhonePairer.h"
#import "JeevesPhoneRegistry.h"
#import "JeevesThemeManager.h"

typedef NS_ENUM(NSInteger, PairSection) {
    PairSectionName,
    PairSectionStatus,
    PairSectionCount
};

typedef NS_ENUM(NSInteger, PairState) {
    PairStateReady,
    PairStateStarting,
    PairStateWaiting,
    PairStateRegistering,
    PairStateFailed,     // pairing failed: start again
    PairStateNotFound,   // paired, but Home Assistant can't see the phone yet: register again
    PairStateDone
};

static NSString * const kCellID = @"PairPhoneCell";

@interface JeevesPairPhoneViewController () <UITextFieldDelegate, JeevesPhonePairerDelegate>
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) JeevesPhonePairer *pairer;
@property (nonatomic, assign) PairState state;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSArray<NSString *> *keys; // from the last pairing
@end

@implementation JeevesPairPhoneViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Pair a Phone";
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.estimatedRowHeight = 44;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    self.nameField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 360, 30)];
    self.nameField.textColor = [theme textColor];
    self.nameField.textAlignment = NSTextAlignmentRight;
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameField.returnKeyType = UIReturnKeyDone;
    self.nameField.delegate = self;
    self.nameField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"e.g. Alex's iPhone"
                                                                           attributes:@{NSForegroundColorAttributeName: [theme secondaryTextColor]}];

    self.pairer = [[JeevesPhonePairer alloc] init];
    self.pairer.delegate = self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        [self.pairer stop];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (NSString *)phoneName {
    return [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)setState:(PairState)state message:(NSString *)message {
    self.state = state;
    self.message = message;
    self.nameField.enabled = (state == PairStateReady || state == PairStateFailed || state == PairStateNotFound);
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return PairSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == PairSectionName) return 1;
    return self.message.length ? 2 : 1; // status message, action button
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == PairSectionName) return nil;
    return [NSString stringWithFormat:
            @"While pairing, this panel shows up as a Bluetooth accessory called “%@”.\n"
            @"• iPhone: open a Bluetooth app such as LightBlue or nRF Connect, connect to “%@” and read its "
            @"characteristic (tap it in LightBlue, or the ↓ button in nRF Connect). The iPhone then asks to pair: tap Pair.\n"
            @"• Android: Settings → Bluetooth → Pair new device → “%@”.\n"
            @"If this panel also asks to pair, tap Pair. Keep the phone near a Bluetooth proxy so Home Assistant can see it. "
            @"Afterwards you can forget “%@” on the phone; tracking keeps working.",
            self.pairer.advertisedName, self.pairer.advertisedName, self.pairer.advertisedName, self.pairer.advertisedName];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCellID];
        cell.backgroundColor = [theme cardBackgroundColor];
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [theme secondaryBackgroundColor];
        cell.selectedBackgroundView = selected;
    }
    cell.textLabel.textColor = [theme textColor];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.numberOfLines = 1;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == PairSectionName) {
        cell.textLabel.text = @"Name";
        cell.accessoryView = self.nameField;
        return cell;
    }

    if (self.message.length && indexPath.row == 0) {
        cell.textLabel.text = self.message;
        cell.textLabel.numberOfLines = 0;
        if (self.state == PairStateFailed || self.state == PairStateNotFound) cell.textLabel.textColor = [theme onColor];
        return cell;
    }

    NSString *title = nil;
    BOOL enabled = YES;
    switch (self.state) {
        case PairStateReady:       title = @"Start Pairing"; break;
        case PairStateStarting:    title = @"Starting…"; enabled = NO; break;
        case PairStateWaiting:     title = @"Stop"; break;
        case PairStateRegistering: title = @"Registering…"; enabled = NO; break;
        case PairStateFailed:      title = @"Start Pairing Again"; break;
        case PairStateNotFound:    title = @"Try Registering Again"; break;
        case PairStateDone:        title = @"Done"; break;
    }
    cell.textLabel.text = title;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = enabled ? [theme accentColor] : [theme secondaryTextColor];
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != PairSectionStatus || (self.message.length && indexPath.row == 0)) return;
    [self.view endEditing:YES];

    switch (self.state) {
        case PairStateReady:
        case PairStateFailed:
            [self startPairing];
            break;
        case PairStateWaiting:
            [self.pairer stop];
            [self setState:PairStateReady message:nil];
            break;
        case PairStateNotFound:
            [self registerKeys];
            break;
        case PairStateDone:
            [self.navigationController popViewControllerAnimated:YES];
            break;
        default:
            break;
    }
}

#pragma mark - Pairing

- (void)startPairing {
    if ([self phoneName].length == 0) {
        [self showMessage:@"Give the phone a name first, such as its owner's name." title:@"Name Needed"];
        return;
    }
    [self setState:PairStateStarting message:nil];
    [self.pairer start];
}

- (void)phonePairerIsWaitingForPhone:(JeevesPhonePairer *)pairer {
    [self setState:PairStateWaiting
           message:[NSString stringWithFormat:@"Waiting for the phone to pair with “%@”…", pairer.advertisedName]];
}

- (void)phonePairer:(JeevesPhonePairer *)pairer didFailWithError:(NSString *)error {
    [self setState:PairStateFailed message:error];
}

- (void)phonePairer:(JeevesPhonePairer *)pairer didPairWithKeys:(NSArray<NSString *> *)keys {
    self.keys = keys;
    [self registerKeys];
}

- (void)registerKeys {
    [self setState:PairStateRegistering message:@"Paired. Registering the phone with Home Assistant…"];
    NSString *name = [self phoneName].length ? [self phoneName] : @"Phone";
    [JeevesPhoneRegistry registerPhoneWithCandidateKeys:self.keys name:name completion:^(JeevesRegisteredPhone *phone, NSString *error) {
        if (!phone) {
            // Most often the phone isn't near a proxy (or is asleep): keep the keys and let them retry
            [self setState:PairStateNotFound message:error];
            return;
        }
        [self setState:PairStateDone
               message:[NSString stringWithFormat:@"%@ is registered. Bermuda will show which room it's in within a minute or so.", name]];
        if (self.onRegistered) self.onRegistered(phone);
    }];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!self.view.window || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
