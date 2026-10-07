#import "JeevesJellyfinLibraryViewController.h"
#import "JeevesJellyfinMediaCell.h"
#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinDetailViewController.h"
#import "JeevesJellyfinShowViewController.h"
#import "UIViewController+JeevesRefresh.h"
#import "JeevesThemeManager.h"

static NSString * const kCellID = @"JeevesJellyfinMediaCell";

@interface JeevesJellyfinLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy)   NSString *libraryID;
@property (nonatomic, copy)   NSString *collectionType;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<JeevesJellyfinItem *> *items;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL exhausted;
@end

@implementation JeevesJellyfinLibraryViewController

- (instancetype)initWithLibraryID:(NSString *)libraryID title:(NSString *)title collectionType:(NSString *)collectionType {
    self = [super init];
    if (self) {
        _libraryID = [libraryID copy];
        _collectionType = [collectionType copy];
        _items = [NSMutableArray array];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [[JeevesThemeManager sharedManager] backgroundColor];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(12, 12, 12, 12);

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[JeevesJellyfinMediaCell class] forCellWithReuseIdentifier:kCellID];
    [self.view addSubview:self.collectionView];

    [self jeeves_installPullToRefreshOnScrollView:self.collectionView];
    [self jeeves_installWakeRefreshObserver];
}

- (void)dealloc {
    [self jeeves_removeWakeRefreshObserver];
    [self jeeves_stopRefreshTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.items.count == 0) {
        [self refreshFromSource:JeevesRefreshSourceManual];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self jeeves_stopRefreshTimer];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.collectionView.collectionViewLayout invalidateLayout];
}

#pragma mark - JeevesRefreshable

- (NSTimeInterval)refreshPollingInterval     { return 0; }
- (BOOL)refreshShouldPollWhenVisible         { return NO; }

- (void)refreshFromSource:(JeevesRefreshSource)source {
    if (self.loading) { [self jeeves_endRefreshing]; return; }
    self.loading = YES;
    self.exhausted = NO;
    [self.items removeAllObjects];
    [self loadNextPageWithStart:0];
}

- (void)loadNextPageWithStart:(NSInteger)start {
    __weak typeof(self) weakSelf = self;
    [[JeevesJellyfinClient sharedClient] fetchItemsInLibrary:self.libraryID collectionType:self.collectionType startIndex:start limit:50 completion:^(NSArray *items, NSError *error) {
        __strong typeof(weakSelf) strong = weakSelf;
        if (!strong) return;
        strong.loading = NO;
        [strong jeeves_endRefreshing];
        if (error || items == nil) return;
        if (items.count == 0) { strong.exhausted = YES; return; }
        [strong.items addObjectsFromArray:items];
        [strong.collectionView reloadData];
    }];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    JeevesJellyfinMediaCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:ip];
    [cell configureWithItem:self.items[ip.item]];

    // Pagination trigger
    if (!self.loading && !self.exhausted && ip.item >= (NSInteger)self.items.count - 20) {
        self.loading = YES;
        [self loadNextPageWithStart:self.items.count];
    }
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
    JeevesJellyfinItem *item = self.items[ip.item];
    UIViewController *next;
    if (item.type == JeevesJellyfinItemTypeSeries) {
        next = [[JeevesJellyfinShowViewController alloc] initWithItem:item mode:JeevesJellyfinShowModeShow];
    } else {
        next = [[JeevesJellyfinDetailViewController alloc] initWithItem:item];
    }
    [self.navigationController pushViewController:next animated:YES];
}

@end
