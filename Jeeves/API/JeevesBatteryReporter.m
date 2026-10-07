#import "JeevesBatteryReporter.h"
#import "HAAPIClient.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

static NSString * const kDefaultsBatteryInstanceId = @"JeevesBatteryInstanceId";

@interface JeevesBatteryReporter ()

@property (nonatomic, copy, readwrite) NSString *instanceIdentifier;
@property (nonatomic, strong) NSTimer *reportTimer;
@property (nonatomic, strong) NSURLSession *session;

@end

@implementation JeevesBatteryReporter

+ (instancetype)sharedReporter {
    static JeevesBatteryReporter *sharedReporter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedReporter = [[self alloc] init];
    });
    return sharedReporter;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        // Enable battery monitoring
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;

        // Short lowercase hex ID; HA webhook IDs are case-sensitive and URL-embedded
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _instanceIdentifier = [d stringForKey:kDefaultsBatteryInstanceId];
        if (_instanceIdentifier.length == 0) {
            NSString *uuid = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
            _instanceIdentifier = [[uuid substringToIndex:8] lowercaseString];
            [d setObject:_instanceIdentifier forKey:kDefaultsBatteryInstanceId];
            [d synchronize];
        }
    }
    return self;
}

- (NSString *)webhookID {
    return [NSString stringWithFormat:@"jeeves_%@_battery", self.instanceIdentifier];
}

- (void)startReporting {
    [self stopReporting];

    // Report immediately
    [self reportNow];

    // Then report every 60 seconds
    self.reportTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                        target:self
                                                      selector:@selector(reportNow)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopReporting {
    [self.reportTimer invalidate];
    self.reportTimer = nil;
}

- (void)reportNow {
    HAAPIClient *client = [HAAPIClient sharedClient];
    if (!client.batteryReportingEnabled || !client.baseURL || client.baseURL.length == 0) {
        return;
    }

    // Build webhook URL from base URL
    NSString *webhookURL = [NSString stringWithFormat:@"%@/api/webhook/%@", client.baseURL, self.webhookID];

    UIDevice *device = [UIDevice currentDevice];

    // Ensure battery monitoring is enabled (must be on main thread for some devices)
    if (!device.batteryMonitoringEnabled) {
        device.batteryMonitoringEnabled = YES;
    }

    // Battery level: 0.0 to 1.0, or -1.0 if unknown
    float batteryLevel = device.batteryLevel;
    UIDeviceBatteryState state = device.batteryState;

    // If battery is full, report 100% even if batteryLevel returns -1
    NSInteger batteryPercent;
    if (state == UIDeviceBatteryStateFull) {
        batteryPercent = 100;
    } else if (batteryLevel >= 0) {
        batteryPercent = (NSInteger)(batteryLevel * 100);
    } else {
        batteryPercent = -1;
    }

    NSLog(@"[BatteryReporter] Raw battery level: %.2f, state: %ld, calculated percent: %ld",
          batteryLevel, (long)state, (long)batteryPercent);

    // Battery state
    NSString *batteryState;
    switch (state) {
        case UIDeviceBatteryStateCharging:
            batteryState = @"charging";
            break;
        case UIDeviceBatteryStateFull:
            batteryState = @"full";
            break;
        case UIDeviceBatteryStateUnplugged:
            batteryState = @"unplugged";
            break;
        default:
            batteryState = @"unknown";
            break;
    }

    // Device info
    NSString *deviceName = device.name;
    NSString *systemVersion = device.systemVersion;

    // Get hardware model (e.g., "iPad4,1" for iPad Air)
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *hardwareModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];

    NSDictionary *payload = @{
        @"battery_level": @(batteryPercent),
        @"battery_state": batteryState,
        @"device_name": deviceName ?: @"Jeeves",
        @"device_model": hardwareModel ?: @"unknown",
        @"ios_version": systemVersion ?: @"unknown",
        @"app": @"Jeeves",
        @"instance_id": self.instanceIdentifier
    };

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError) {
        NSLog(@"[BatteryReporter] JSON error: %@", jsonError);
        return;
    }

    NSURL *url = [NSURL URLWithString:webhookURL];
    if (!url) {
        NSLog(@"[BatteryReporter] Invalid webhook URL: %@", webhookURL);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = jsonData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[BatteryReporter] Webhook error: %@", error.localizedDescription);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                NSLog(@"[BatteryReporter] Reported battery: %ld%% (%@)", (long)batteryPercent, batteryState);
            } else {
                NSLog(@"[BatteryReporter] Webhook returned status: %ld", (long)httpResponse.statusCode);
            }
        }
    }];

    [task resume];
}

@end
