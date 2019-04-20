#import "LocationPlugin.h"

#ifdef COCOAPODS
@import CoreLocation;
#else
#import <CoreLocation/CoreLocation.h>
#endif

@interface LocationPlugin() <FlutterStreamHandler, CLLocationManagerDelegate> 
@property (strong, nonatomic) CLLocationManager *clLocationManager;
@property (copy, nonatomic)   FlutterResult      flutterResult;
@property (assign, nonatomic) BOOL               locationWanted;
@property (assign, nonatomic) BOOL               permissionWanted;

@property (copy, nonatomic)   FlutterEventSink   flutterEventSink;
@property (assign, nonatomic) BOOL               flutterListening;
@property (assign, nonatomic) BOOL               hasInit;
@end

@implementation LocationPlugin {
    UIViewController *_viewController;
    FlutterEngine *_headlessRunner;
    FlutterMethodChannel *channel;
    FlutterMethodChannel *backgroundChannel;
    FlutterEventChannel *stream;
    NSObject<FlutterPluginRegistrar> *_registrar;
}

static LocationPlugin *instance = nil;
static FlutterPluginRegistrantCallback registerPlugins = nil;
static BOOL initialized = NO;

#pragma mark FlutterPlugin Methods


+(void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    @synchronized(self) {
    if (instance == nil) {
      instance = [[LocationPlugin alloc] init:registrar];
      [registrar addApplicationDelegate:instance];
    }
  }
}

+ (void)setPluginRegistrantCallback:(FlutterPluginRegistrantCallback)callback {
    registerPlugins = callback;
}

- (instancetype)init:(NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");

    _headlessRunner = [[FlutterEngine alloc] initWithName:@"FlutterLocationIsolate" project:nil allowHeadlessExecution:YES];
    _registrar = registrar;

    channel = [FlutterMethodChannel methodChannelWithName:@"lyokone/location" binaryMessenger:registrar.messenger];
    [registrar addMethodCallDelegate:self channel:channel];

    stream = [FlutterEventChannel eventChannelWithName:@"lyokone/locationstream" binaryMessenger:registrar.messenger];  
    [stream setStreamHandler:self];

    backgroundChannel = [FlutterMethodChannel methodChannelWithName:@"lyokone/location_background" binaryMessenger:_headlessRunner];

    return self;
}

-(instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];

    if (self) {
        self.locationWanted = NO;
        self.permissionWanted = NO;
        self.flutterListening = NO;
        self.hasInit = NO;
    }
    return self;
}
    
-(void)initLocation {
    if (!(self.hasInit)) {
        self.hasInit = YES;
        
        if ([CLLocationManager locationServicesEnabled]) {
            self.clLocationManager = [[CLLocationManager alloc] init];
            self.clLocationManager.delegate = self;
            self.clLocationManager.desiredAccuracy = kCLLocationAccuracyBest;
        }
    }
}

-(void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    [self initLocation];
    if ([call.method isEqualToString:@"changeSettings"]) {
        if ([CLLocationManager locationServicesEnabled]) {
            NSDictionary *dictionary = @{
                @"0" : @(kCLLocationAccuracyKilometer),
                @"1" : @(kCLLocationAccuracyHundredMeters),
                @"2" : @(kCLLocationAccuracyNearestTenMeters),
                @"3" : @(kCLLocationAccuracyBest),
                @"4" : @(kCLLocationAccuracyBestForNavigation)
            };

            self.clLocationManager.desiredAccuracy = [dictionary[call.arguments[@"accuracy"]] doubleValue];
            double distanceFilter = [call.arguments[@"distanceFilter"] doubleValue];
            if (distanceFilter == 0){
                distanceFilter = kCLDistanceFilterNone;
            }
            self.clLocationManager.distanceFilter = distanceFilter;
            result(@(1));
        }
    } else if ([call.method isEqualToString:@"getLocation"]) {
        if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusDenied && [CLLocationManager locationServicesEnabled])
        {
            // Location services are requested but user has denied
            result([FlutterError errorWithCode:@"PERMISSION_DENIED"
                                   message:@"The user explicitly denied the use of location services for this app or location services are currently disabled in Settings."
                                   details:nil]);
            return;
        }
        
        self.flutterResult = result;
        self.locationWanted = YES;
        
        if ([self isPermissionGranted]) {
            [self.clLocationManager startUpdatingLocation];
        } else {
            [self requestPermission];
            if ([self isPermissionGranted]) {
                [self.clLocationManager startUpdatingLocation];
            }
        }
    } else if ([call.method isEqualToString:@"hasPermission"]) {
        if ([self isPermissionGranted]) {
            result(@(1));
        } else {
            result(@(0));
        }
    } else if ([call.method isEqualToString:@"requestPermission"]) {
        if ([self isPermissionGranted]) {
            result(@(1));
        } else {
            self.flutterResult = result;
            self.permissionWanted = YES;
            [self requestPermission];
        }
    } else if ([call.method isEqualToString:@"serviceEnabled"]) {
        if ([CLLocationManager locationServicesEnabled]) {
            result(@(1));
        } else {
            result(@(0));
        }
    } else if ([call.method isEqualToString:@"requestService"]) {
        if ([CLLocationManager locationServicesEnabled]) {
            result(@(1));
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Location is Disabled"
                message:@"To use location, go to your Settings App > Privacy > Location Services."
                delegate:self
                cancelButtonTitle:@"Cancel"
                otherButtonTitles:nil];
            [alert show];
            result(@(0));
        }
    } else if([call.method isEqualToString:@"registerBackgroundLocation"]) {
        @synchronized(self) {
            initialized = YES;
        }
        
        if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedAlways && [CLLocationManager locationServicesEnabled])
        {
            [self requestBackgroundPermission];
        } 

        
        int64_t rawHandle = [call.arguments[@"rawHandle"] longLongValue];
        int64_t rawCallback = [call.arguments[@"rawCallback"] longLongValue];
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        [preferences setObject:[NSNumber numberWithLongLong:rawHandle] forKey:@"rawHandle"];
        [preferences setObject:[NSNumber numberWithLongLong:rawCallback] forKey:@"rawCallback"];
        [preferences synchronize];
        FlutterCallbackInformation *info = [FlutterCallbackCache lookupCallbackInformation:rawHandle];
        NSAssert(info != nil, @"failed to find callback");
        NSString *entrypoint = info.callbackName;
        NSString *uri = info.callbackLibraryPath;
        [_headlessRunner runWithEntrypoint:entrypoint libraryURI:uri];
        NSAssert(registerPlugins != nil, @"failed to set registerPlugins");
        registerPlugins(_headlessRunner);

        result(@(1));
        
    } else if([call.method isEqualToString:@"removeBackgroundLocation"]) {
        [self.clLocationManager stopMonitoringSignificantLocationChanges];
    } else {
        result(FlutterMethodNotImplemented);
    }
}



-(void) requestPermission {
    if ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"] != nil) {
        [self.clLocationManager requestWhenInUseAuthorization];
    }
    else {
        [NSException raise:NSInternalInconsistencyException format:@"To use location in iOS8 and above you need to define either NSLocationWhenInUseUsageDescription or NSLocationAlwaysUsageDescription in the app bundle's Info.plist file"];
    }
}

-(void) requestBackgroundPermission {
    if ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationAlwaysAndWhenInUseUsageDescription"] != nil) {
        NSLog(@"Request background location");
        [self.clLocationManager requestAlwaysAuthorization];
    }
    else {
        [NSException raise:NSInternalInconsistencyException format:@"To use location in iOS8 and above you need to define either NSLocationWhenInUseUsageDescription or NSLocationAlwaysUsageDescription in the app bundle's Info.plist file"];
    }
}



-(BOOL) isPermissionGranted {
    BOOL isPermissionGranted = NO;
    switch ([CLLocationManager authorizationStatus]) {
        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            // Location services are available
            isPermissionGranted = YES;
            break;
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            // Location services are requested but user has denied / the app is restricted from getting location
            isPermissionGranted = NO;
            break;
        case kCLAuthorizationStatusNotDetermined:
            // Location services never requested / the user still haven't decide
            isPermissionGranted = NO;
            break;
        default:
            isPermissionGranted = NO;
            break;
    }
    
    return isPermissionGranted;
}

-(FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    self.flutterEventSink = events;
    self.flutterListening = YES;

    if ([self isPermissionGranted]) {
        [self.clLocationManager startUpdatingLocation];
    } else {
        [self requestPermission];
    }

    return nil;
}

-(FlutterError*)onCancelWithArguments:(id)arguments {
    self.flutterListening = NO;
    [self.clLocationManager stopUpdatingLocation];
    return nil;
}

#pragma mark - CLLocationManagerDelegate Methods

-(void)locationManager:(CLLocationManager*)manager didUpdateLocations:(NSArray<CLLocation*>*)locations {
    CLLocation *location = locations.firstObject;
    NSTimeInterval timeInSeconds = [location.timestamp timeIntervalSince1970];
    NSDictionary<NSString*,NSNumber*>* coordinatesDict = @{
                                                          @"latitude": @(location.coordinate.latitude),
                                                          @"longitude": @(location.coordinate.longitude),
                                                          @"accuracy": @(location.horizontalAccuracy),
                                                          @"altitude": @(location.altitude),
                                                          @"speed": @(location.speed),
                                                          @"speed_accuracy": @(0.0),
                                                          @"heading": @(location.course),
                                                          @"time": @((double) timeInSeconds)
                                                          };

    if (self.locationWanted) {
        self.locationWanted = NO;
        self.flutterResult(coordinatesDict);
    }
    if (self.flutterListening) {
        self.flutterEventSink(coordinatesDict);
    } else {
        [self.clLocationManager stopUpdatingLocation];
    }

    // Background checks
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];

    // [preferences setObject:rawHandle forKey:@"rawHandle"];
    // [preferences setObject:rawCallback forKey:@"rawCallback"];
    // HighScore = [[[NSUserDefaults standardUserDefaults] objectForKey:@"HighScoreSaved"] longLongValue];

    @synchronized(self) {
        if (initialized) {
            NSMutableArray *listData = [[NSMutableArray alloc] init];

            for (CLLocation *location in locations) {
                    NSTimeInterval timeInSeconds = [location.timestamp timeIntervalSince1970];
                    NSDictionary<NSString*,NSNumber*>* coordinatesDict = @{
                        @"latitude": @(location.coordinate.latitude),
                        @"longitude": @(location.coordinate.longitude),
                        @"accuracy": @(location.horizontalAccuracy),
                        @"altitude": @(location.altitude),
                        @"speed": @(location.speed),
                        @"speed_accuracy": @(0.0),
                        @"heading": @(location.course),
                        @"time": @((double) timeInSeconds)
                        };

                    [listData addObject:coordinatesDict];

            }

            if ([preferences objectForKey:@"rawCallback"] != nil && backgroundChannel != nil)
            {
                NSLog(@"Trying to send background updates");
                int64_t rawCallback = [[preferences objectForKey:@"rawCallback"] longLongValue];
                [backgroundChannel
                    invokeMethod:@""
                        arguments:@[
                        @(rawCallback), listData
                        ]];

            }
        }
    }
    

}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusDenied) {
        // The user denied authorization
        NSLog(@"User denied permissions");
        if (self.permissionWanted) {
            self.permissionWanted = NO;
            self.flutterResult(@(0));
        }
        
    }
    else if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        NSLog(@"User granted permissions");
        if (self.permissionWanted) {
            self.permissionWanted = NO;
            self.flutterResult(@(1));
        }

        if (self.locationWanted || self.flutterListening) {
            [self.clLocationManager startUpdatingLocation];
        }
    } else if (status == kCLAuthorizationStatusAuthorizedAlways) {
        NSLog(@"User granted background permissions");
        [self.clLocationManager startMonitoringSignificantLocationChanges];
    }
}

@end
