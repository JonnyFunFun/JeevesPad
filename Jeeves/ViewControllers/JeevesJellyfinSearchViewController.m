#import "JeevesJellyfinSearchViewController.h"
#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinMediaCell.h"
#import "JeevesJellyfinDetailViewController.h"
#import "JeevesJellyfinShowViewController.h"
#import "UIViewController+JeevesRefresh.h"
#import "JeevesThemeManager.h"

static NSString * const kCellID = @"JeevesJellyfinMediaCell";

@interface JeevesJellyfinSearchViewController () <UISearchBarDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<JeevesJellyfinItem *> *results;
@property (nonatomic, copy)   NSString *pendingQuery;
@end

@implementation JeevesJellyfinSearchViewController

- (instancetype)initWithQuery:(NSString *)query {
    self = [super init];
    if (self) {
        _pendingQuery = [query copy];
        _results = @[];
        self.title = @"Search";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.view.backgroundColor = [theme backgroundColor];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search Jellyfin";
    self.searchBar.text = self.pendingQuery;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.view addSubview:self.searchBar];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(12, 12, 12, 12);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[JeevesJellyfinMediaCell class] forCellWithReuseIdentifier:kCellID];
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor      constraintEqualToAnchor:self.view.topAnchor],
        [self.searchBar.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.collectionView.topAnchor      constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.collectionView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self jeeves_installPullToRefreshOnScrollView:self.collectionView];
    [self jeeves_installWakeRefreshObserver];

    if (self.pendingQuery.length > 0) {
        [self refreshFromSource:JeevesRefreshSourceManual];
    }
}

- (void)dealloc {
    [self jeeves_removeWakeRefreshObserver];
    [self jeeves_stopRefreshTimer];
}

#pragma mark - JeevesRefreshable

- (BOOL)refreshShouldPollWhenVisible { return NO; }

- (void)refreshFromSource:(JeevesRefreshSource)source {
    NSString *q = self.searchBar.text ?: self.pendingQuery;
    if (q.length == 0) { [self jeeves_endRefreshing]; self.results = @[]; [self.collectionView reloadData]; return; }
    [[JeevesJellyfinClient sharedClient] searchQuery:q completion:^(NSArray *items, NSError *error) {
        [self jeeves_endRefreshing];
        if (items) {
            self.results = items;
            [self.collectionView reloadData];
        }
    }];
}

#pragma mark - SearchBar (debounced)

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performDebouncedSearch) object:nil];
    [self performSelector:@selector(performDebouncedSearch) withObject:nil afterDelay:0.3];
}

- (void)performDebouncedSearch {
    [self refreshFromSource:JeevesRefreshSourceManual];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self refreshFromSource:JeevesRefreshSourceManual];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.results.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    JeevesJellyfinMediaCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:ip];
    [cell configureWithItem:self.results[ip.item]];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    BOOL portrait = cv.bounds.size.height > cv.bounds.size.width;
    NSInteger cols = portrait ? 3 : 5;
    CGFloat totalSpacing = 12 * (cols + 1);
    CGFloat w = (cv.bounds.size.width - totalSpacing) / cols;
    CGFloat h = w * 1.5 + 36;
    return CGSizeMake(w, h);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [cv deselectItemAtIndexPath:ip animated:YES];
    JeevesJellyfinItem *item = self.results[ip.item];
    UIViewController *next;
    if (item.type == JeevesJellyfinItemTypeSeries) {
        next = [[JeevesJellyfinShowViewController alloc] initWithItem:item mode:JeevesJellyfinShowModeShow];
    } else if (item.type == JeevesJellyfinItemTypeSeason) {
        next = [[JeevesJellyfinShowViewController alloc] initWithItem:item mode:JeevesJellyfinShowModeSeason];
    } else {
        next = [[JeevesJellyfinDetailViewController alloc] initWithItem:item];
    }
    [self.navigationController pushViewController:next animated:YES];
}

@end
