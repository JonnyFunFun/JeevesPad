#import "JeevesGuidedAccessViewController.h"
#import "JeevesGuidedAccess.h"
#import "JeevesThemeManager.h"

typedef NS_ENUM(NSInteger, GuidedSection) {
    GuidedSectionStatus,
    GuidedSectionCode,
    GuidedSectionCount
};

static NSString * const kCellID = @"GuidedAccessCell";

@interface JeevesGuidedAccessViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, assign) BOOL busy;
@end

@implementation JeevesGuidedAccessViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Guided Access";
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.codeField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
    self.codeField.textColor = [theme textColor];
    self.codeField.textAlignment = NSTextAlignmentRight;
    self.codeField.secureTextEntry = YES;
    self.codeField.keyboardType = UIKeyboardTypeNumberPad;
    self.codeField.delegate = self;
    self.codeField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"None"
                                                                           attributes:@{NSForegroundColorAttributeName: [theme secondaryTextColor]}];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged)
                                                 name:JeevesGuidedAccessDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveCode];
}

- (void)statusChanged {
    self.busy = NO;
    [self.tableView reloadData];
}

- (void)saveCode {
    // The code can't be changed during Guided Access, or anyone could change it
    if ([JeevesGuidedAccess sharedManager].active || self.codeField.text.length == 0) return;
    [JeevesGuidedAccess sharedManager].unlockCode = self.codeField.text;
    self.codeField.text = nil;
    [self.tableView reloadData];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self saveCode];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return GuidedSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == GuidedSectionStatus) return 2;
    return [JeevesGuidedAccess sharedManager].unlockCode && ![JeevesGuidedAccess sharedManager].active ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == GuidedSectionStatus ? @"Guided Access" : @"Unlock Code";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    JeevesGuidedAccess *guided = [JeevesGuidedAccess sharedManager];
    if (section == GuidedSectionStatus) {
        NSString *about = @"Guided Access keeps this iPad in Jeeves. It can also be turned on and off from Home Assistant. "
                          @"Jeeves can only start it on a supervised iPad whose configuration profile allows Jeeves "
                          @"for Single App Mode.";
        return guided.lastError ? [NSString stringWithFormat:@"%@\n\n%@", guided.lastError, about] : about;
    }
    if (guided.active) return @"The unlock code can't be changed during Guided Access.";
    return @"Ending Guided Access (or maintenance mode) on this iPad asks for this code. It's shared with your other "
           @"iPads (fleet sync) and can be set from Home Assistant.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    JeevesGuidedAccess *guided = [JeevesGuidedAccess sharedManager];
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
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == GuidedSectionStatus) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Status";
            cell.detailTextLabel.text = guided.active ? @"On" : @"Off";
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.textColor = self.busy ? [theme secondaryTextColor] : [theme accentColor];
            cell.textLabel.text = self.busy ? @"Please wait…"
                                : guided.active ? @"End Guided Access…" : @"Start Guided Access";
        }
        return cell;
    }

    if (indexPath.row == 0) {
        cell.textLabel.text = guided.unlockCode ? @"New code" : @"Code";
        cell.accessoryView = self.codeField;
        self.codeField.enabled = !guided.active;
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = @"Remove Code";
        cell.textLabel.textColor = [UIColor colorWithRed:0.86 green:0.3 blue:0.27 alpha:1];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    JeevesGuidedAccess *guided = [JeevesGuidedAccess sharedManager];
    if (indexPath.section == GuidedSectionCode) {
        if (indexPath.row == 1) {
            guided.unlockCode = nil;
            [self.tableView reloadData];
        }
        return;
    }
    if (indexPath.row != 1 || self.busy) return;
    [self.view endEditing:YES];
    if (guided.active) {
        [self askForCodeThenEnd];
    } else {
        [self setWanted:YES];
    }
}

- (void)setWanted:(BOOL)wanted {
    self.busy = YES;
    [self.tableView reloadData];
    [[JeevesGuidedAccess sharedManager] setWanted:wanted completion:^(BOOL success) {
        self.busy = NO;
        [self.tableView reloadData];
    }];
}

- (void)askForCodeThenEnd {
    JeevesGuidedAccess *guided = [JeevesGuidedAccess sharedManager];
    if (!guided.unlockCode) {
        [self setWanted:NO];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"End Guided Access"
                                                                   message:@"Enter the unlock code."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.keyboardType = UIKeyboardTypeNumberPad;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"End" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if ([guided checkUnlockCode:weakAlert.textFields.firstObject.text ?: @""]) {
            [self setWanted:NO];
        } else {
            UIAlertController *wrong = [UIAlertController alertControllerWithTitle:@"Wrong Code" message:nil
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [wrong addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:wrong animated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
