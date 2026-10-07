#import <UIKit/UIKit.h>

@class JeevesGridLayout;

@protocol JeevesGridLayoutDelegate <NSObject>
- (NSInteger)numberOfColumnsInGridLayout:(JeevesGridLayout *)layout;
// Span in grid units: width = columns, height = half-rows (2 half-rows = a square cell)
- (CGSize)gridLayout:(JeevesGridLayout *)layout spanForItemAtIndexPath:(NSIndexPath *)indexPath;
@end

// Grid of square cells, split vertically into half-rows, where items can span
// multiple columns/half-rows (card sizes), packed first-fit in item order.
// Single section only.
@interface JeevesGridLayout : UICollectionViewLayout

@property (nonatomic, weak) id<JeevesGridLayoutDelegate> delegate;
@property (nonatomic, assign) CGFloat spacing;
@property (nonatomic, assign) UIEdgeInsets sectionInset;

@end
