#import "JeevesJellyfinViewController.h"
#import "JeevesJellyfinLibraryViewController.h"
#import "JeevesJellyfinSearchViewController.h"
#import "JeevesJellyfinShowViewController.h"
#import "JeevesJellyfinDetailViewController.h"
#import "JeevesJellyfinNowPlayingViewController.h"
#import "JeevesJellyfinRowView.h"
#import "JeevesJellyfinNowPlayingPill.h"
#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinSession.h"
#import "UIViewController+JeevesRefresh.h"
#import "JeevesThemeManager.h"

@interface JeevesJellyfinViewController () <UISearchBarDelegate, JeevesJellyfinRowViewDelegate, JeevesJellyfinNowPlayingPillDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) JeevesJellyfinRowView *continueRow;
@property (nonatomic, strong) JeevesJellyfinRowView *recentRow;
@property (nonatomic, strong) NSMutableArray<JeevesJellyfinRowView *> *sectionRows;
@property (nonatomic, strong) NSArray *sections; // raw Jellyfin library views
@property (nonatomic, strong) JeevesJellyfinNowPlayingPill *pill;
@property (nonatomic, assign) BOOL didLoadInitial;
@end

@implementation JeevesJellyfinViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Jellyfin";
    self.view.backgroundColor = [[JeevesThemeManager sharedManager] backgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(closeTapped)];

    [self setupViews];
    [self jeeves_installPullToRefreshOnScrollView:self.scrollView];
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

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:^{
        // Posters and backdrops aren't needed outside Jellyfin; free them for the dashboard
        [[JeevesJellyfinClient sharedClient] clearImageCache];
    }];
}

- (void)setupViews {
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = [theme backgroundColor];
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"Search Jellyfin";
    self.searchBar.delegate = self;
    self.searchBar.barTintColor = [theme backgroundColor];
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    [self.contentView addSubview:self.searchBar];

    self.continueRow = [self makeRowWithTitle:@"Continue Watching"];
    [self.contentView addSubview:self.continueRow];

    self.recentRow = [self makeRowWithTitle:@"Recently Added"];
    [self.contentView addSubview:self.recentRow];

    self.sectionRows = [NSMutableArray array];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor      constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor      constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor  constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor   constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor    constraintEqualToAnchor:self.scrollView.widthAnchor],

        [self.searchBar.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.searchBar.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],

        [self.continueRow.topAnchor      constraintEqualToAnchor:self.searchBar.bottomAnchor constant:8],
        [self.continueRow.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.continueRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.continueRow.heightAnchor   constraintEqualToConstant:260],

        [self.recentRow.topAnchor      constraintEqualToAnchor:self.continueRow.bottomAnchor constant:8],
        [self.recentRow.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.recentRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.recentRow.heightAnchor   constraintEqualToConstant:260],
    ]];

    // Now Playing pill, pinned above bottom
    self.pill = [[JeevesJellyfinNowPlayingPill alloc] init];
    self.pill.translatesAutoresizingMaskIntoConstraints = NO;
    self.pill.hidden = YES;
    self.pill.delegate = self;
    [self.view addSubview:self.pill];
    [NSLayoutConstraint activateConstraints:@[
        [self.pill.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.pill.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.pill.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor constant:-12],
        [self.pill.heightAnchor   constraintEqualToConstant:66],
    ]];
}

- (JeevesJellyfinRowView *)makeRowWithTitle:(NSString *)title {
    JeevesJellyfinRowView *row = [[JeevesJellyfinRowView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.title = title;
    row.delegate = self;
    return row;
}

#pragma mark - JeevesRefreshable

- (NSTimeInterval)refreshPollingInterval { return 5.0; }
- (BOOL)refreshShouldPollWhenVisible     { return YES; }

- (void)refreshFromSource:(JeevesRefreshSource)source {
    BOOL fullRefresh = (source == JeevesRefreshSourcePullToRefresh
                       || source == JeevesRefreshSourceWakeFromSleep
                       || source == JeevesRefreshSourceManual);
    if (fullRefresh) {
        [self loadSections];
    }
    [self loadContinueWatching];
    [self loadRecentlyAdded];
    [self loadActiveSessions];
}

- (void)loadSections {
    __weak typeof(self) weakSelf = self;
    [[JeevesJellyfinClient sharedClient] fetchLibrariesWithCompletion:^(NSArray<NSDictionary *> *sections, NSError *error) {
        __strong typeof(weakSelf) strong = weakSelf;
        if (!strong) return;
        if (error) { [strong jeeves_endRefreshing]; return; }
        strong.sections = sections;
        [strong rebuildSectionRows];
        [strong jeeves_endRefreshing];
    }];
}

- (void)rebuildSectionRows {
    UIView *previous = self.recentRow;
    NSInteger toReuse = MIN(self.sections.count, self.sectionRows.count);
    for (NSInteger i = 0; i < toReuse; i++) {
        JeevesJellyfinRowView *row = self.sectionRows[i];
        NSDictionary *sec = self.sections[i];
        row.title = sec[@"Name"];
        row.sectionID = sec[@"Id"];
        row.collectionType = sec[@"CollectionType"];
        [self loadItemsForSection:sec into:row];
        previous = row;
    }
    // Add new
    for (NSInteger i = toReuse; i < (NSInteger)self.sections.count; i++) {
        NSDictionary *sec = self.sections[i];
        JeevesJellyfinRowView *row = [self makeRowWithTitle:sec[@"Name"]];
        row.sectionID = sec[@"Id"];
        row.collectionType = sec[@"CollectionType"];
        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor      constraintEqualToAnchor:previous.bottomAnchor constant:8],
            [row.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [row.heightAnchor   constraintEqualToConstant:260],
        ]];
        [self.sectionRows addObject:row];
        [self loadItemsForSection:sec into:row];
        previous = row;
    }
    // Remove excess
    while (self.sectionRows.count > (NSUInteger)self.sections.count) {
        JeevesJellyfinRowView *r = self.sectionRows.lastObject;
        [r removeFromSuperview];
        [self.sectionRows removeLastObject];
    }
    // Anchor last row to contentView bottom
    if (previous && previous != self.recentRow) {
        [self.contentView.bottomAnchor constraintEqualToAnchor:previous.bottomAnchor constant:80].active = YES;
    }
}

- (void)loadItemsForSection:(NSDictionary *)sec into:(JeevesJellyfinRowView *)row {
    [[JeevesJellyfinClient sharedClient] fetchItemsInLibrary:sec[@"Id"] collectionType:sec[@"CollectionType"] startIndex:0 limit:20 completion:^(NSArray *items, NSError *error) {
        if (items) [row setItems:items];
    }];
}

- (void)loadContinueWatching {
    [[JeevesJellyfinClient sharedClient] fetchContinueWatchingWithCompletion:^(NSArray *items, NSError *err) {
        if (items) [self.continueRow setItems:items];
    }];
}

- (void)loadRecentlyAdded {
    [[JeevesJellyfinClient sharedClient] fetchRecentlyAddedWithCompletion:^(NSArray *items, NSError *err) {
        if (items) [self.recentRow setItems:items];
    }];
}

- (void)loadActiveSessions {
    [[JeevesJellyfinClient sharedClient] fetchActiveSessionsWithCompletion:^(NSArray *sessions, NSError *err) {
        JeevesJellyfinSession *active = sessions.firstObject;
        if (active) {
            self.pill.hidden = NO;
            [self.pill configureWithSession:active];
        } else {
            self.pill.hidden = YES;
        }
    }];
}

#pragma mark - JeevesJellyfinRowViewDelegate

- (void)jellyfinRowView:(JeevesJellyfinRowView *)row didTapItem:(JeevesJellyfinItem *)item {
    UIViewController *next = nil;
    switch (item.type) {
        case JeevesJellyfinItemTypeSeries:
            next = [[JeevesJellyfinShowViewController alloc] initWithItem:item mode:JeevesJellyfinShowModeShow];
            break;
        case JeevesJellyfinItemTypeSeason:
            next = [[JeevesJellyfinShowViewController alloc] initWithItem:item mode:JeevesJellyfinShowModeSeason];
            break;
        default:
            next = [[JeevesJellyfinDetailViewController alloc] initWithItem:item];
            break;
    }
    if (next) [self.navigationController pushViewController:next animated:YES];
}

- (void)jellyfinRowViewDidTapHeader:(JeevesJellyfinRowView *)row {
    if (row.sectionID.length > 0) {
        JeevesJellyfinLibraryViewController *vc = [[JeevesJellyfinLibraryViewController alloc] initWithLibraryID:row.sectionID
                                                                                               title:row.title
                                                                                      collectionType:row.collectionType];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

#pragma mark - Pill

- (void)jellyfinNowPlayingPillDidTap:(JeevesJellyfinNowPlayingPill *)pill {
    JeevesJellyfinNowPlayingViewController *vc = [[JeevesJellyfinNowPlayingViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // No-op; user must press search button (avoids unneeded requests)
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
    JeevesJellyfinSearchViewController *vc = [[JeevesJellyfinSearchViewController alloc] initWithQuery:@""];
    [self.navigationController pushViewController:vc animated:YES];
    return NO;
}

@end
