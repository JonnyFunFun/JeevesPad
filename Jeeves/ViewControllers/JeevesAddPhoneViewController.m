#import "JeevesAddPhoneViewController.h"
#import "JeevesPhoneRegistry.h"
#import "JeevesThemeManager.h"

typedef NS_ENUM(NSInteger, AddPhoneSection) {
    AddPhoneSectionDetails,
    AddPhoneSectionRegister,
    AddPhoneSectionCount
};

static NSString * const kCellID = @"AddPhoneCell";

@interface JeevesAddPhoneViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, assign) BOOL busy;
@end

@implementation JeevesAddPhoneViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Add a Phone";
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.tableView.backgroundColor = [theme backgroundColor];
    self.tableView.separatorColor = [theme separatorColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.nameField = [self fieldWithPlaceholder:@"e.g. Alex's iPhone"];
    self.nameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameField.returnKeyType = UIReturnKeyNext;

    self.keyField = [self fieldWithPlaceholder:@"Hex or base64"];
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.keyField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.keyField.font = [UIFont fontWithName:@"Menlo" size:15] ?: self.keyField.font;
    self.keyField.returnKeyType = UIReturnKeyGo;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 360, 30)];
    field.textColor = [theme textColor];
    field.textAlignment = NSTextAlignmentRight;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.delegate = self;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
                                                                  attributes:@{NSForegroundColorAttributeName: [theme secondaryTextColor]}];
    return field;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField) {
        [self.keyField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
        [self registerPhone];
    }
    return YES;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return AddPhoneSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == AddPhoneSectionDetails ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == AddPhoneSectionDetails) {
        return @"The key is the phone's Bluetooth Identity Resolving Key (IRK). A phone only shares it with devices "
               @"it pairs with, so get it from one of these:\n"
               @"• A Mac the iPhone is paired with: open Keychain Access, search for the phone's Bluetooth "
               @"entry and copy its Remote IRK.\n"
               @"• An ESP32 running ESPresense or IRK Capture: pair the phone with it and copy the key it shows.\n"
               @"• A Linux computer the phone is paired with: the IdentityResolvingKey in "
               @"/var/lib/bluetooth/<adapter>/<phone>/info.";
    }
    return @"Keep the phone unlocked and near one of your Bluetooth proxies while registering: Home Assistant only "
           @"accepts a key for a phone it can see. Bermuda starts tracking the phone within a minute or so.";
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
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == AddPhoneSectionDetails) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Name";
            cell.accessoryView = self.nameField;
        } else {
            cell.textLabel.text = @"Key";
            cell.accessoryView = self.keyField;
        }
        return cell;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.text = self.busy ? @"Registering…" : @"Register Phone";
    cell.textLabel.textColor = self.busy ? [theme secondaryTextColor] : [theme accentColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == AddPhoneSectionRegister) {
        [self registerPhone];
    }
}

#pragma mark - Registering

- (void)registerPhone {
    if (self.busy) return;
    [self.view endEditing:YES];

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:whitespace];
    NSString *key = [self.keyField.text stringByTrimmingCharactersInSet:whitespace];
    if (name.length == 0) {
        [self showMessage:@"Give the phone a name, such as its owner's name." title:@"Name Needed"];
        return;
    }
    if (key.length == 0) {
        [self showMessage:@"Paste the phone's Bluetooth key. The notes below say where to find it." title:@"Key Needed"];
        return;
    }

    [self setBusy:YES];
    [JeevesPhoneRegistry registerPhoneWithKey:key name:name completion:^(JeevesRegisteredPhone *phone, NSString *error) {
        [self setBusy:NO];
        if (!phone) {
            [self showMessage:error title:@"Couldn't Register Phone"];
            return;
        }
        if (self.onRegistered) self.onRegistered(phone);
        if (!self.view.window) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Phone Registered"
                                                                       message:[NSString stringWithFormat:@"Home Assistant is now tracking %@, and Bermuda will show which room it's in.", name]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.nameField.enabled = !busy;
    self.keyField.enabled = !busy;
    self.navigationItem.hidesBackButton = busy;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:AddPhoneSectionRegister] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!self.view.window || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
