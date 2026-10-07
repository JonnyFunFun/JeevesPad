#import "JeevesJellyfinShowViewController.h"
#import "JeevesJellyfinMediaCell.h"
#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinDetailViewController.h"
#import "UIViewController+JeevesRefresh.h"
#import "JeevesThemeManager.h"

static NSString * const kCellID = @"JeevesJellyfinMediaCell";

@interface JeevesJellyfinShowViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) JeevesJellyfinItem *parentItem;
@property (nonatomic, assign) JeevesJellyfinShowMode mode;
@property (nonatomic, strong) UIImageView *artView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<JeevesJellyfinItem *> *children;
@end

@implementation JeevesJellyfinShowViewController

- (instancetype)initWithItem:(JeevesJellyfinItem *)item mode:(JeevesJellyfinShowMode)mode {
    self = [super init];
    if (self) {
        _parentItem = item;
        _mode = mode;
        self.title = item.displayTitle;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.view.backgroundColor = [theme backgroundColor];

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = [theme backgroundColor];

    self.artView = [[UIImageView alloc] init];
    self.artView.translatesAutoresizingMaskIntoConstraints = NO;
    self.artView.contentMode = UIViewContentModeScaleAspectFill;
    self.artView.clipsToBounds = YES;
    self.artView.layer.cornerRadius = 6;
    self.artView.backgroundColor = [theme cardBackgroundColor];
    [header addSubview:self.artView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    self.titleLabel.textColor = [theme textColor];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.text = self.parentItem.displayTitle;
    [header addSubview:self.titleLabel];

    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont systemFontOfSize:13];
    self.summaryLabel.textColor = [theme secondaryTextColor];
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.text = self.parentItem.summary;
    [header addSubview:self.summaryLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.artView.topAnchor      constraintEqualToAnchor:header.topAnchor constant:12],
        [self.artView.leadingAnchor  constraintEqualToAnchor:header.leadingAnchor constant:12],
        [self.artView.widthAnchor    constraintEqualToConstant:110],
        [self.artView.heightAnchor   constraintEqualToConstant:165],

        [self.titleLabel.topAnchor      constraintEqualToAnchor:self.artView.topAnchor],
        [self.titleLabel.leadingAnchor  constraintEqualToAnchor:self.artView.trailingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12],

        [self.summaryLabel.topAnchor      constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.summaryLabel.leadingAnchor  constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12],
        [self.summaryLabel.bottomAnchor   constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-12],
    ]];

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

    [self.view addSubview:header];
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor      constraintEqualToAnchor:self.view.topAnchor],
        [header.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor   constraintEqualToConstant:190],

        [self.collectionView.topAnchor      constraintEqualToAnchor:header.bottomAnchor],
        [self.collectionView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self jeeves_installPullToRefreshOnScrollView:self.collectionView];
    [self jeeves_installWakeRefreshObserver];

    NSString *thumbKey = self.parentItem.art ?: self.parentItem.thumb;
    if (thumbKey.length > 0) {
        [[JeevesJellyfinClient sharedClient] loadImageForThumbKey:thumbKey size:CGSizeMake(110, 165) completion:^(UIImage *img, NSError *e) {
            self.artView.image = img;
        }];
    }
}

- (void)dealloc {
    [self jeeves_removeWakeRefreshObserver];
    [self jeeves_stopRefreshTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshFromSource:JeevesRefreshSourceManual];
}

#pragma mark - JeevesRefreshable

- (BOOL)refreshShouldPollWhenVisible { return NO; }

- (void)refreshFromSource:(JeevesRefreshSource)source {
    [[JeevesJellyfinClient sharedClient] fetchChildrenOfItem:self.parentItem completion:^(NSArray *items, NSError *error) {
        [self jeeves_endRefreshing];
        if (items) {
            self.children = items;
            [self.collectionView reloadData];
        }
    }];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.children.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    JeevesJellyfinMediaCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:ip];
    [cell configureWithItem:self.children[ip.item]];
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
    JeevesJellyfinItem *child = self.children[ip.item];
    UIViewController *next;
    if (child.type == JeevesJellyfinItemTypeSeason) {
        next = [[JeevesJellyfinShowViewController alloc] initWithItem:child mode:JeevesJellyfinShowModeSeason];
    } else {
        next = [[JeevesJellyfinDetailViewController alloc] initWithItem:child];
    }
    [self.navigationController pushViewController:next animated:YES];
}

@end
