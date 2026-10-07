#import "JeevesJellyfinRowView.h"
#import "JeevesJellyfinMediaCell.h"
#import "JeevesJellyfinItem.h"
#import "JeevesThemeManager.h"

static NSString * const kCellID = @"JeevesJellyfinMediaCell";

@interface JeevesJellyfinRowView () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *headerButton;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation JeevesJellyfinRowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        JeevesThemeManager *theme = [JeevesThemeManager sharedManager];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont boldSystemFontOfSize:18];
        _titleLabel.textColor = [theme textColor];
        [self addSubview:_titleLabel];

        _headerButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _headerButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_headerButton addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_headerButton];

        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.minimumLineSpacing = 12;
        layout.minimumInteritemSpacing = 12;
        layout.sectionInset = UIEdgeInsetsMake(0, 12, 0, 12);

        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.showsHorizontalScrollIndicator = NO;
        _collectionView.dataSource = self;
        _collectionView.delegate   = self;
        [_collectionView registerClass:[JeevesJellyfinMediaCell class] forCellWithReuseIdentifier:kCellID];
        [self addSubview:_collectionView];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor      constraintEqualToAnchor:self.topAnchor constant:8],
            [_titleLabel.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],

            [_headerButton.topAnchor      constraintEqualToAnchor:_titleLabel.topAnchor],
            [_headerButton.bottomAnchor   constraintEqualToAnchor:_titleLabel.bottomAnchor],
            [_headerButton.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
            [_headerButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_collectionView.topAnchor      constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8],
            [_collectionView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
            [_collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_collectionView.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.titleLabel.text = title;
}

- (void)setItems:(NSArray *)items {
    _items = items;
    [self.collectionView reloadData];
}

- (void)headerTapped {
    if ([self.delegate respondsToSelector:@selector(jellyfinRowViewDidTapHeader:)]) {
        [self.delegate jellyfinRowViewDidTapHeader:self];
    }
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    JeevesJellyfinMediaCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCellID forIndexPath:ip];
    if (ip.item < (NSInteger)self.items.count) {
        [cell configureWithItem:self.items[ip.item]];
    }
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat h = cv.bounds.size.height - 4;
    CGFloat w = (h - 36) / 1.5; // 36 = title+subtitle area
    if (w < 80) w = 80;
    return CGSizeMake(w, h);
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [cv deselectItemAtIndexPath:ip animated:YES];
    if (ip.item >= (NSInteger)self.items.count) return;
    JeevesJellyfinItem *item = self.items[ip.item];
    if ([self.delegate respondsToSelector:@selector(jellyfinRowView:didTapItem:)]) {
        [self.delegate jellyfinRowView:self didTapItem:item];
    }
}

@end
