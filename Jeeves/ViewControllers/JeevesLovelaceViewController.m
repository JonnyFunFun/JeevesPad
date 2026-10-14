#import "JeevesLovelaceViewController.h"
#import "JeevesLovelaceDashboard.h"
#import "HAWebSocketClient.h"
#import "HAAPIClient.h"
#import "HAEntity.h"
#import "JeevesLightToggleCell.h"
#import "JeevesLightControlsView.h"
#import "JeevesGridLayout.h"
#import "JeevesEntityMoreInfoViewController.h"
#import "JeevesThemeManager.h"
#import "UIViewController+JeevesRefresh.h"

static NSString * const kEntityCellID = @"LovelaceEntityCell";
static NSString * const kTextCellID   = @"LovelaceTextCell";
static NSString * const kDefaultsDashboard = @"JeevesLovelaceDashboard"; // url_path; "" = default dashboard
static NSString * const kDefaultsViewIndex = @"JeevesLovelaceViewIndex";
static const CGFloat kSpacing = 12.0;
static const CGFloat kTabBarHeight = 44.0;
static const NSInteger kMaxTextHalfRows = 8;
static const NSInteger kFullWidthSpan = 99; // clamped to the column count by the layout

#pragma mark - Text cell

// Headings, markdown text, placeholders for unsupported cards and missing entities
@interface JeevesLovelaceTextCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@end

@implementation JeevesLovelaceTextCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 16;
        self.contentView.layer.masksToBounds = YES;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.numberOfLines = 2;
        [self.contentView addSubview:_titleLabel];

        _bodyLabel = [[UILabel alloc] init];
        _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bodyLabel.numberOfLines = 0;
        [self.contentView addSubview:_bodyLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_bodyLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
            [_bodyLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_bodyLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_bodyLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)configureAsHeading:(NSString *)title {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.titleLabel.textColor = [theme textColor];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.text = title;
    self.bodyLabel.text = nil;
}

- (void)configureWithTitle:(NSString *)title body:(NSString *)body muted:(BOOL)muted {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.contentView.backgroundColor = muted ? [[theme cardBackgroundColor] colorWithAlphaComponent:0.5] : [theme cardBackgroundColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.textColor = muted ? [theme secondaryTextColor] : [theme textColor];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.text = title;
    self.bodyLabel.font = [UIFont systemFontOfSize:muted ? 12 : 15];
    self.bodyLabel.textColor = muted ? [theme secondaryTextColor] : [theme textColor];
    self.bodyLabel.text = body;
}

@end

#pragma mark - View controller

@interface JeevesLovelaceViewController () <UICollectionViewDataSource, UICollectionViewDelegate, JeevesGridLayoutDelegate,
                                            JeevesLightToggleCellDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *tabBar;
@property (nonatomic, strong) NSArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSLayoutConstraint *collectionTopConstraint;

@property (nonatomic, strong) NSArray<NSDictionary *> *dashboards; // non-default dashboards from HA
@property (nonatomic, strong) JeevesLovelaceDashboard *dashboard;
@property (nonatomic, assign) NSInteger viewIndex;
@property (nonatomic, strong) NSDictionary<NSString *, HAEntity *> *entitiesById;
@property (nonatomic, assign) BOOL isInteracting;
@property (nonatomic, assign) BOOL didLoadInitial;
@end

@implementation JeevesLovelaceViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.view.backgroundColor = [theme backgroundColor];
    self.title = @"Dashboard";

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:self
                                                                                          action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Dashboards"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(pickDashboardTapped)];

    // View tabs (frame-based buttons in a horizontally scrolling strip)
    self.tabBar = [[UIScrollView alloc] init];
    self.tabBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabBar.showsHorizontalScrollIndicator = NO;
    self.tabBar.hidden = YES;
    [self.view addSubview:self.tabBar];

    JeevesGridLayout *layout = [[JeevesGridLayout alloc] init];
    layout.spacing = kSpacing;
    layout.sectionInset = UIEdgeInsetsMake(kSpacing, kSpacing, kSpacing, kSpacing);
    layout.delegate = self;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[JeevesLightToggleCell class] forCellWithReuseIdentifier:kEntityCellID];
    [self.collectionView registerClass:[JeevesLovelaceTextCell class] forCellWithReuseIdentifier:kTextCellID];
    [self.view addSubview:self.collectionView];

    // Long-press opens more info, like dashboard cards
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.delegate = self;
    [self.collectionView addGestureRecognizer:longPress];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:17];
    self.statusLabel.textColor = [theme secondaryTextColor];
    [self.view addSubview:self.statusLabel];

    self.collectionTopConstraint = [self.collectionView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabBar.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor],
        [self.tabBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tabBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tabBar.heightAnchor constraintEqualToConstant:kTabBarHeight],

        self.collectionTopConstraint,
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
    ]];

    self.viewIndex = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsViewIndex];
    [self jeeves_installPullToRefreshOnScrollView:self.collectionView];
    [self jeeves_installWakeRefreshObserver];
}

- (void)dealloc {
    [self jeeves_removeWakeRefreshObserver];
    [self jeeves_stopRefreshTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didLoadInitial) {
        self.didLoadInitial = YES;
        [self refreshFromSource:JeevesRefreshSourceManual];
    }
    [self jeeves_startRefreshTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self jeeves_stopRefreshTimer];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTabButtons];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - JeevesRefreshable

- (NSTimeInterval)refreshPollingInterval { return 2.0; }

- (void)refreshFromSource:(JeevesRefreshSource)source {
    if (source != JeevesRefreshSourceTimer) {
        [self loadDashboard];
    }
    [self loadStates];
}

- (void)loadStates {
    [[HAAPIClient sharedClient] fetchStatesWithCompletion:^(NSArray<HAEntity *> *entities, NSError *error) {
        if (!entities) return;
        NSMutableDictionary *byId = [NSMutableDictionary dictionaryWithCapacity:entities.count];
        for (HAEntity *entity in entities) {
            if (entity.entityId) byId[entity.entityId] = entity;
        }
        self.entitiesById = byId;
        // Don't rebuild cells under the user's finger or behind a presented screen
        if (!self.isInteracting && ![JeevesLightControlsView isUserAdjusting] && !self.presentedViewController) {
            [self.collectionView reloadData];
        }
    }];
}

- (NSString *)selectedDashboardPath {
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsDashboard];
    return path.length > 0 ? path : nil;
}

- (void)loadDashboard {
    if (!self.dashboard) [self showStatus:@"Loading dashboard…"];
    NSString *path = [self selectedDashboardPath];

    [HAWebSocketClient fetchDashboardsWithCompletion:^(NSArray<NSDictionary *> *dashboards, NSError *error) {
        if (dashboards) self.dashboards = dashboards;
        [self updateTitle];
    }];

    [HAWebSocketClient fetchLovelaceConfigForDashboard:path completion:^(NSDictionary *config, NSError *error) {
        [self jeeves_endRefreshing];
        if (!config) {
            BOOL autoGenerated = [error.userInfo[@"code"] isEqualToString:@"config_not_found"];
            self.dashboard = nil;
            [self reloadTabs];
            [self showStatus:autoGenerated
                ? @"This dashboard is generated automatically by Home Assistant. To show it in Jeeves, open it in "
                  @"Home Assistant and choose \"Take control\", or pick another dashboard."
                : [NSString stringWithFormat:@"Couldn't load the dashboard: %@", error.localizedDescription ?: @"unknown error"]];
            return;
        }
        NSError *parseError = nil;
        JeevesLovelaceDashboard *dashboard = [JeevesLovelaceDashboard dashboardFromConfig:config error:&parseError];
        self.dashboard = dashboard;
        if (!dashboard) {
            [self reloadTabs];
            [self showStatus:parseError.localizedDescription];
            return;
        }
        if (self.viewIndex >= (NSInteger)dashboard.views.count) self.viewIndex = 0;
        [self updateTitle];
        [self reloadTabs];
        [self showCurrentView];
    }];
}

- (void)showStatus:(NSString *)status {
    self.statusLabel.text = status;
    self.statusLabel.hidden = (status.length == 0);
    self.collectionView.hidden = (status.length > 0);
}

- (void)updateTitle {
    NSString *path = [self selectedDashboardPath];
    NSString *title = self.dashboard.title;
    if (!title) {
        title = @"Overview";
        for (NSDictionary *d in self.dashboards) {
            if ([d[@"url_path"] isEqual:path]) title = d[@"title"] ?: path;
        }
    }
    self.title = title;
}

- (JeevesLovelaceView *)currentView {
    NSArray *views = self.dashboard.views;
    return (self.viewIndex >= 0 && self.viewIndex < (NSInteger)views.count) ? views[self.viewIndex] : nil;
}

- (void)showCurrentView {
    JeevesLovelaceView *view = [self currentView];
    if (!view) {
        [self showStatus:@"This dashboard has no views."];
        return;
    }
    [self showStatus:(view.items.count == 0 ? @"This view has no cards Jeeves can show." : nil)];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    [self.collectionView setContentOffset:CGPointZero animated:NO];
}

#pragma mark - Dashboard picker

- (void)pickDashboardTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Dashboards"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *current = [self selectedDashboardPath] ?: @"";
    NSMutableArray *choices = [NSMutableArray arrayWithObject:@{@"title": @"Overview", @"url_path": @""}];
    for (NSDictionary *d in self.dashboards) {
        if ([d[@"url_path"] isKindOfClass:[NSString class]]) [choices addObject:d];
    }
    for (NSDictionary *choice in choices) {
        NSString *path = choice[@"url_path"];
        NSString *title = [choice[@"title"] isKindOfClass:[NSString class]] ? choice[@"title"] : path;
        if ([path isEqualToString:current]) title = [NSString stringWithFormat:@"✓ %@", title];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setObject:path forKey:kDefaultsDashboard];
            [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kDefaultsViewIndex];
            self.viewIndex = 0;
            self.dashboard = nil;
            [self reloadTabs];
            [self loadDashboard];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - View tabs

- (void)reloadTabs {
    for (UIButton *b in self.tabButtons) [b removeFromSuperview];
    NSMutableArray *buttons = [NSMutableArray array];
    NSArray *views = self.dashboard.views;
    for (NSUInteger i = 0; i < views.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        button.layer.cornerRadius = 8;
        [button setTitle:[views[i] title] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.tabBar addSubview:button];
        [buttons addObject:button];
    }
    self.tabButtons = buttons;

    // Only show tabs when there's a choice of views
    BOOL showTabs = views.count > 1;
    self.tabBar.hidden = !showTabs;
    self.collectionTopConstraint.constant = showTabs ? kTabBarHeight : 0;
    [self updateTabSelection];
    [self.view setNeedsLayout];
}

- (void)layoutTabButtons {
    CGFloat x = kSpacing;
    for (UIButton *button in self.tabButtons) {
        CGFloat width = ceil([button sizeThatFits:CGSizeMake(CGFLOAT_MAX, 32)].width);
        button.frame = CGRectMake(x, 6, width, 32);
        x += width + 8;
    }
    self.tabBar.contentSize = CGSizeMake(x + kSpacing - 8, kTabBarHeight);
}

- (void)updateTabSelection {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    for (UIButton *button in self.tabButtons) {
        BOOL selected = (button.tag == self.viewIndex);
        button.backgroundColor = selected ? [theme onColor] : [theme cardBackgroundColor];
        [button setTitleColor:(selected ? [UIColor blackColor] : [theme textColor]) forState:UIControlStateNormal];
    }
}

- (void)tabTapped:(UIButton *)button {
    self.viewIndex = button.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:self.viewIndex forKey:kDefaultsViewIndex];
    [self updateTabSelection];
    [self showCurrentView];
}

#pragma mark - Items

- (NSArray<JeevesLovelaceItem *> *)items {
    return [self currentView].items ?: @[];
}

- (HAEntity *)entityForItem:(JeevesLovelaceItem *)item {
    return item.kind == JeevesLovelaceItemKindEntity ? self.entitiesById[item.entityId] : nil;
}

// Markdown shown as plain text: drop heading markers and emphasis
- (NSString *)plainTextFromMarkdown:(NSString *)markdown {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [markdown componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = line;
        while ([trimmed hasPrefix:@"#"]) trimmed = [trimmed substringFromIndex:1];
        trimmed = [trimmed stringByReplacingOccurrencesOfString:@"**" withString:@""];
        trimmed = [trimmed stringByReplacingOccurrencesOfString:@"__" withString:@""];
        [lines addObject:[trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    }
    return [[lines componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - JeevesGridLayoutDelegate

- (NSInteger)numberOfColumnsInGridLayout:(JeevesGridLayout *)layout {
    // Same scale as room dashboards: 5 columns in landscape, 3 in portrait
    return self.view.bounds.size.width > self.view.bounds.size.height ? 5 : 3;
}

- (CGSize)gridLayout:(JeevesGridLayout *)layout spanForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *items = [self items];
    if (indexPath.item >= (NSInteger)items.count) return CGSizeMake(1, 2);
    JeevesLovelaceItem *item = items[indexPath.item];
    switch (item.kind) {
        case JeevesLovelaceItemKindHeading:
            return CGSizeMake(kFullWidthSpan, 1);
        case JeevesLovelaceItemKindText:
            return CGSizeMake(kFullWidthSpan, [self halfRowsForText:[self plainTextFromMarkdown:item.text]]);
        default:
            return CGSizeMake(1, 2); // Small card
    }
}

// Enough half-rows to fit the text at full width (capped)
- (NSInteger)halfRowsForText:(NSString *)text {
    NSInteger columns = [self numberOfColumnsInGridLayout:(JeevesGridLayout *)self.collectionView.collectionViewLayout];
    CGFloat width = self.collectionView.bounds.size.width - kSpacing * 2;
    CGFloat unit = (width - kSpacing * (columns - 1)) / columns;
    CGFloat halfRow = MAX(1, (unit - kSpacing) / 2);
    CGFloat textHeight = [text boundingRectWithSize:CGSizeMake(MAX(1, width - 24), CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15]}
                                            context:nil].size.height;
    CGFloat needed = textHeight + 24;
    NSInteger halfRows = (NSInteger)ceil((needed + kSpacing) / (halfRow + kSpacing));
    return MIN(kMaxTextHalfRows, MAX(1, halfRows));
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self items].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    JeevesLovelaceItem *item = [self items][indexPath.item];
    HAEntity *entity = [self entityForItem:item];
    if (entity) {
        JeevesLightToggleCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kEntityCellID forIndexPath:indexPath];
        cell.delegate = self;
        // Dashboards scroll, so vertical drags must scroll rather than set brightness
        cell.allowsBrightnessDrag = NO;
        [cell configureWithEntity:entity displayName:item.name];
        return cell;
    }

    JeevesLovelaceTextCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kTextCellID forIndexPath:indexPath];
    switch (item.kind) {
        case JeevesLovelaceItemKindHeading:
            [cell configureAsHeading:item.name];
            break;
        case JeevesLovelaceItemKindText:
            [cell configureWithTitle:nil body:[self plainTextFromMarkdown:item.text] muted:NO];
            break;
        case JeevesLovelaceItemKindUnsupported:
            [cell configureWithTitle:item.name body:[NSString stringWithFormat:@"%@ card isn't supported in Jeeves", item.text] muted:YES];
            break;
        case JeevesLovelaceItemKindEntity:
            // Not (yet) in the state list: still loading, or the entity no longer exists
            [cell configureWithTitle:item.name ?: item.entityId
                                body:(self.entitiesById ? @"Entity not found" : @"Loading…")
                               muted:YES];
            break;
    }
    return cell;
}

#pragma mark - Long press / more info

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![JeevesLightControlsView touchIsInsideLightControls:touch];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:[gesture locationInView:self.collectionView]];
    if (!indexPath || indexPath.item >= (NSInteger)[self items].count) return;
    [self presentMoreInfoForEntity:[self entityForItem:[self items][indexPath.item]]];
}

- (void)presentMoreInfoForEntity:(HAEntity *)entity {
    if (!entity || self.presentedViewController) return;
    // No dashboard ID: these cards are defined in Home Assistant, not customizable in Jeeves
    JeevesEntityMoreInfoViewController *moreInfo = [[JeevesEntityMoreInfoViewController alloc] initWithEntity:entity dashboardID:nil];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:moreInfo];
    [[JeevesThemeManager sharedManager] applyThemeToNavigationBar:nav.navigationBar];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - JeevesLightToggleCellDelegate

- (void)lightToggleCell:(JeevesLightToggleCell *)cell didToggleEntity:(HAEntity *)entity toState:(BOOL)on {
    NSString *entityId = cell.entityId;
    if (!entityId) return;
    self.entitiesById[entityId].state = on ? @"on" : @"off";
    if (on) {
        [[HAAPIClient sharedClient] turnOnEntity:entityId completion:nil];
    } else {
        [[HAAPIClient sharedClient] turnOffEntity:entityId completion:nil];
    }
}

- (void)lightToggleCell:(JeevesLightToggleCell *)cell didSetBrightness:(NSInteger)brightness forEntity:(HAEntity *)entity {
    NSString *entityId = cell.entityId;
    if (!entityId) return;
    // Convert 1-100% to HA's 0-255 scale, rounding up so 1% stays on
    NSInteger haBrightness = MAX(3, (MAX(1, brightness) * 255 + 99) / 100);
    [[HAAPIClient sharedClient] setLightBrightness:entityId brightness:haBrightness completion:nil];
}

- (void)lightToggleCell:(JeevesLightToggleCell *)cell didTriggerScript:(HAEntity *)entity {
    if (cell.entityId) [[HAAPIClient sharedClient] turnOnEntity:cell.entityId completion:nil];
}

- (void)lightToggleCell:(JeevesLightToggleCell *)cell didChangeInteractionState:(BOOL)isInteracting {
    self.isInteracting = isInteracting;
}

- (void)lightToggleCellDidTapReadOnlyEntity:(JeevesLightToggleCell *)cell {
    [self presentMoreInfoForEntity:self.entitiesById[cell.entityId]];
}

@end
