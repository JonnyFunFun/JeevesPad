#import <Foundation/Foundation.h>

@class HAEntity;

NS_ASSUME_NONNULL_BEGIN

typedef void (^HACompletionBlock)(BOOL success, id _Nullable result, NSError * _Nullable error);
typedef void (^HAEntitiesBlock)(NSArray<HAEntity *> * _Nullable entities, NSError * _Nullable error);

// Notification posted when connection status changes
extern NSString * const HAAPIClientConnectionStatusChangedNotification;

@interface HAAPIClient : NSObject

+ (instancetype)sharedClient;

@property (nonatomic, strong, nullable) NSString *baseURL;
@property (nonatomic, strong, nullable) NSString *accessToken;
@property (nonatomic, assign) BOOL batteryReportingEnabled;
@property (nonatomic, assign, readonly) BOOL isConnected;

- (void)configureWithBaseURL:(NSString *)baseURL accessToken:(NSString *)accessToken;
- (BOOL)isConfigured;
// Re-reads settings from NSUserDefaults (e.g. after another iPad shared its settings)
- (void)reloadFromDefaults;

- (void)fetchStatesWithCompletion:(HAEntitiesBlock)completion;
- (void)fetchStateForEntity:(NSString *)entityId completion:(void (^)(HAEntity * _Nullable entity, NSError * _Nullable error))completion;
- (void)callService:(NSString *)domain
            service:(NSString *)service
           entityId:(NSString *)entityId
         parameters:(NSDictionary * _Nullable)parameters
         completion:(nullable HACompletionBlock)completion;

- (void)turnOnEntity:(NSString *)entityId completion:(nullable HACompletionBlock)completion;
- (void)turnOffEntity:(NSString *)entityId completion:(nullable HACompletionBlock)completion;
- (void)setLightBrightness:(NSString *)entityId brightness:(NSInteger)brightness completion:(nullable HACompletionBlock)completion;
- (void)setLightColor:(NSString *)entityId red:(NSInteger)red green:(NSInteger)green blue:(NSInteger)blue completion:(nullable HACompletionBlock)completion;

- (nullable NSString *)cameraStreamURLForEntity:(NSString *)entityId;

// Weather
- (void)fetchWeatherForecastForEntity:(NSString *)entityId completion:(nullable HACompletionBlock)completion;

// Any REST call (path starts with /api/); `body` is sent as JSON. Completes on the main
// queue with the HTTP status (0 if the request failed) and the parsed JSON response.
- (void)sendRequestWithMethod:(NSString *)method
                         path:(NSString *)path
                         body:(nullable id)body
                   completion:(void (^)(NSInteger statusCode, id _Nullable json, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
