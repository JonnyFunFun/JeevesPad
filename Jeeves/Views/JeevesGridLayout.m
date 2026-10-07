#import "JeevesGridLayout.h"
#import "JeevesCardSettings.h"

@interface JeevesGridLayout ()
@property (nonatomic, strong) NSArray<UICollectionViewLayoutAttributes *> *itemAttributes;
@property (nonatomic, assign) CGSize contentSize;
@end

@implementation JeevesGridLayout

- (void)prepareLayout {
    [super prepareLayout];
    UICollectionView *cv = self.collectionView;
    NSInteger count = cv.numberOfSections > 0 ? [cv numberOfItemsInSection:0] : 0;
    NSInteger columns = MAX(1, [self.delegate numberOfColumnsInGridLayout:self]);

    CGFloat width = cv.bounds.size.width - self.sectionInset.left - self.sectionInset.right;
    CGFloat unit = MAX(0, (width - self.spacing * (columns - 1)) / columns);
    // Two half-rows plus the spacing between them make one square cell
    CGFloat halfRow = MAX(0, (unit - self.spacing) / 2);

    NSMutableArray<NSValue *> *spans = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        NSIndexPath *ip = [NSIndexPath indexPathForItem:i inSection:0];
        [spans addObject:[NSValue valueWithCGSize:[self.delegate gridLayout:self spanForItemAtIndexPath:ip]]];
    }
    NSInteger rows = 0;
    NSArray<NSValue *> *origins = [JeevesCardSettings packSpans:spans columns:columns rowCount:&rows];

    NSMutableArray *attributes = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        CGPoint origin = [origins[i] CGPointValue];
        CGSize span = [spans[i] CGSizeValue];
        NSInteger w = MIN(MAX(1, (NSInteger)span.width), columns);
        NSInteger h = MAX(1, (NSInteger)span.height);
        UICollectionViewLayoutAttributes *attr =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
        attr.frame = CGRectMake(self.sectionInset.left + origin.x * (unit + self.spacing),
                                self.sectionInset.top + origin.y * (halfRow + self.spacing),
                                w * unit + (w - 1) * self.spacing,
                                h * halfRow + (h - 1) * self.spacing);
        [attributes addObject:attr];
    }
    self.itemAttributes = attributes;

    CGFloat height = rows > 0 ? rows * halfRow + (rows - 1) * self.spacing : 0;
    self.contentSize = CGSizeMake(cv.bounds.size.width, self.sectionInset.top + height + self.sectionInset.bottom);
}

- (CGSize)collectionViewContentSize {
    return self.contentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *visible = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attr in self.itemAttributes) {
        if (CGRectIntersectsRect(attr.frame, rect)) [visible addObject:attr];
    }
    return visible;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.item < (NSInteger)self.itemAttributes.count ? self.itemAttributes[indexPath.item] : nil;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    // Unit size depends on width (and columns on orientation); vertical scrolling doesn't matter
    return newBounds.size.width != self.collectionView.bounds.size.width
        || newBounds.size.height != self.collectionView.bounds.size.height;
}

@end
