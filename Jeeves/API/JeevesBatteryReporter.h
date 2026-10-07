#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JeevesBatteryReporter : NSObject

+ (instancetype)sharedReporter;

// Start/stop periodic reporting (every 60 seconds)
- (void)startReporting;
- (void)stopReporting;

// Manual report trigger
- (void)reportNow;

// Persistent per-install identifier, so several devices can report to one Home Assistant
@property (nonatomic, copy, readonly) NSString *instanceIdentifier;

// Home Assistant webhook ID this install posts to: jeeves_<instanceIdentifier>_battery
@property (nonatomic, copy, readonly) NSString *webhookID;

@end

NS_ASSUME_NONNULL_END
