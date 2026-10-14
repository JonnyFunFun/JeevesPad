#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "JeevesIdleManager.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        // JeevesApplication sees every touch, for the idle timeout and screen dimming
        return UIApplicationMain(argc, argv, NSStringFromClass([JeevesApplication class]), NSStringFromClass([AppDelegate class]));
    }
}
