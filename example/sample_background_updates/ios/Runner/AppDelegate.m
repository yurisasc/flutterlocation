#include "AppDelegate.h"
#include "GeneratedPluginRegistrant.h"

#import <location/LocationPlugin.h>

@implementation AppDelegate

void registerPlugins(NSObject<FlutterPluginRegistry>* registry) {
  [GeneratedPluginRegistrant registerWithRegistry:registry];
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  [LocationPlugin setPluginRegistrantCallback:registerPlugins];

  // Override point for customization after application launch.
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

@end
