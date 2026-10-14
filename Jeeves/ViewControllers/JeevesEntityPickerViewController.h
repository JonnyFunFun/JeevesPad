#import <UIKit/UIKit.h>

@class HAEntity;

NS_ASSUME_NONNULL_BEGIN

// Searchable list of entities to choose one from, optionally preceded by fixed
// options (e.g. "Automatic", "None"). Pops itself after a choice.
@interface JeevesEntityPickerViewController : UITableViewController

// completion receives the chosen entity ID (optionIndex -1), or nil and the index
// of the chosen option
- (instancetype)initWithTitle:(NSString *)title
                     entities:(NSArray<HAEntity *> *)entities
                      options:(nullable NSArray<NSString *> *)options
             selectedEntityId:(nullable NSString *)selectedEntityId
               selectedOption:(NSInteger)selectedOption
                   completion:(void (^)(NSString * _Nullable entityId, NSInteger optionIndex))completion;

@end

NS_ASSUME_NONNULL_END
