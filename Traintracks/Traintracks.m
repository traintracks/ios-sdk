//
// Traintracks.m
//

#ifndef TRAINTRACKS_DEBUG
#define TRAINTRACKS_DEBUG 0
#endif

#if TRAINTRACKS_DEBUG
#   define TRAINTRACKS_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define TRAINTRACKS_LOG(...)
#endif


#import "Traintracks.h"
#import "TTLocationManagerDelegate.h"
#import "TTARCMacros.h"
#import "TTConstants.h"
#import "TTDeviceInfo.h"
#import "TTDatabaseHelper.h"
#import "TTUtils.h"
#import "TTIdentify.h"
#import <math.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#include <sys/types.h>
#include <sys/sysctl.h>

@interface Traintracks()

@property (nonatomic, strong) NSOperationQueue *backgroundQueue;
@property (nonatomic, strong) NSOperationQueue *initializerQueue;
@property (nonatomic, assign) BOOL initialized;
@property (nonatomic, assign) BOOL sslPinningEnabled;
@property (nonatomic, assign) long long sessionId;

@end

NSString *const kTTSessionStartEvent = @"sessionStart";
NSString *const kTTSessionEndEvent = @"sessionEnd";
NSString *const kTTRevenueEvent = @"revenueAmount";

static NSString *const BACKGROUND_QUEUE_NAME = @"BACKGROUND";
static NSString *const DATABASE_VERSION = @"databaseVersion";
static NSString *const DEVICE_ID = @"deviceId";
static NSString *const EVENTS = @"events";
static NSString *const EVENT_ID = @"eventId";
static NSString *const PREVIOUS_SESSION_ID = @"previousSessionId";
static NSString *const PREVIOUS_SESSION_TIME = @"previousSessionTime";
static NSString *const MAX_EVENT_ID = @"maxEventId";
static NSString *const MAX_IDENTIFY_ID = @"maxIdentifyId";
static NSString *const OPT_OUT = @"optOut";
static NSString *const USER_ID = @"userId";
static NSString *const USER_NAME = @"userName";
static NSString *const SEQUENCE_NUMBER = @"sequenceNumber";


@implementation Traintracks {
    NSString *_eventsDataPath;
    NSMutableDictionary *_propertyList;
    NSString *_propertyListPath;

    BOOL _updateScheduled;
    BOOL _updatingCurrently;
    UIBackgroundTaskIdentifier _uploadTaskID;

    TTDeviceInfo *_deviceInfo;
    BOOL _useAdvertisingIdForDeviceId;

    CLLocation *_lastKnownLocation;
    BOOL _locationListeningEnabled;
    CLLocationManager *_locationManager;
    TTLocationManagerDelegate *_locationManagerDelegate;

    BOOL _inForeground;

    BOOL _backoffUpload;
    int _backoffUploadBatchSize;

    BOOL _offline;
    
    NSDateFormatter *_dateFormatter;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma mark - Static methods

+ (Traintracks *)instance {
    static Traintracks *_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}




+ (void)logEvent:(NSString*) eventType {
    [[Traintracks instance] logEvent:eventType];
}

+ (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties {
    [[Traintracks instance] logEvent:eventType withEventProperties:eventProperties];
}

+ (void)uploadEvents {
    [[Traintracks instance] uploadEvents];
}

+ (void)setUserProperties:(NSDictionary*) userProperties {
    [[Traintracks instance] setUserProperties:userProperties];
}

+ (void)setUserName:(NSString*) userName {
    [[Traintracks instance] setUserName:userName];
}

+ (void)enableLocationListening {
    [[Traintracks instance] enableLocationListening];
}

+ (void)disableLocationListening {
    [[Traintracks instance] disableLocationListening];
}

+ (void)useAdvertisingIdForDeviceId {
    [[Traintracks instance] useAdvertisingIdForDeviceId];
}

+ (void)printEventsCount {
    [[Traintracks instance] printEventsCount];
}

+ (NSString*)getDeviceId {
    return [[Traintracks instance] getDeviceId];
}

+ (void)updateLocation
{
    [[Traintracks instance] updateLocation];
}


#pragma mark - Main class methods
- (id)init
{
    if (self = [super init]) {
        
        _dateFormatter = [[NSDateFormatter alloc]init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"];
        _initialized = NO;
        _locationListeningEnabled = YES;
        _sessionId = -1;
        _updateScheduled = NO;
        _updatingCurrently = NO;
        _useAdvertisingIdForDeviceId = NO;
        _backoffUpload = NO;
        _offline = NO;

        self.eventUploadThreshold = kTTEventUploadThreshold;
        self.eventMaxCount = kTTEventMaxCount;
        self.eventUploadMaxBatchSize = kTTEventUploadMaxBatchSize;
        self.eventUploadPeriodSeconds = kTTEventUploadPeriodSeconds;
        self.minTimeBetweenSessionsMillis = kTTMinTimeBetweenSessionsMillis;
        _backoffUploadBatchSize = self.eventUploadMaxBatchSize;

        _initializerQueue = [[NSOperationQueue alloc] init];
        _backgroundQueue = [[NSOperationQueue alloc] init];
        // Force method calls to happen in FIFO order by only allowing 1 concurrent operation
        [_backgroundQueue setMaxConcurrentOperationCount:1];
        // Ensure initialize finishes running asynchronously before other calls are run
        [_backgroundQueue setSuspended:YES];
        // Name the queue so runOnBackgroundQueue can tell which queue an operation is running
        _backgroundQueue.name = BACKGROUND_QUEUE_NAME;
        
        [_initializerQueue addOperationWithBlock:^{
            
            _deviceInfo = [[TTDeviceInfo alloc] init];

            _uploadTaskID = UIBackgroundTaskInvalid;
            
            NSString *eventsDataDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
            _propertyListPath = SAFE_ARC_RETAIN([eventsDataDirectory stringByAppendingPathComponent:@"traintracks.plist"]);

            // Load propertyList object
            _propertyList = SAFE_ARC_RETAIN([self deserializePList:_propertyListPath]);
            if (!_propertyList) {
                _propertyList = SAFE_ARC_RETAIN([NSMutableDictionary dictionary]);
                [_propertyList setObject:[NSNumber numberWithInt:1] forKey:DATABASE_VERSION];
                BOOL success = [self savePropertyList];
                if (!success) {
                    NSLog(@"ERROR: Unable to save propertyList to file on initialization");
                }
            } else {
                TRAINTRACKS_LOG(@"Loaded from %@", _propertyListPath);
            }

            // try to restore previous session
            long long previousSessionId = [self previousSessionId];
            if (previousSessionId >= 0) {
                _sessionId = previousSessionId;
            }

            [self initializeDeviceId];

            [_backgroundQueue setSuspended:NO];
        }];

        // CLLocationManager must be created on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            Class CLLocationManager = NSClassFromString(@"CLLocationManager");
            _locationManager = [[CLLocationManager alloc] init];
            _locationManagerDelegate = [[TTLocationManagerDelegate alloc] init];
            SEL setDelegate = NSSelectorFromString(@"setDelegate:");
            [_locationManager performSelector:setDelegate withObject:_locationManagerDelegate];
        });

        [self addObservers];
    }
    return self;
};


- (void) addObservers
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(enterForeground)
                   name:UIApplicationWillEnterForegroundNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(enterBackground)
                   name:UIApplicationDidEnterBackgroundNotification
                 object:nil];
}

- (void) removeObservers
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void) dealloc {
    [self removeObservers];

    // Release properties
    SAFE_ARC_RELEASE(_apiKey);
    SAFE_ARC_RELEASE(_apiSecret);
    SAFE_ARC_RELEASE(_backgroundQueue);
    SAFE_ARC_RELEASE(_deviceId);
    SAFE_ARC_RELEASE(_userId);
    SAFE_ARC_RELEASE(_userName);
    SAFE_ARC_RELEASE(_buildName);
    SAFE_ARC_RELEASE(_endpointUrl);

    // Release instance variables
    SAFE_ARC_RELEASE(_deviceInfo);
    SAFE_ARC_RELEASE(_initializerQueue);
    SAFE_ARC_RELEASE(_lastKnownLocation);
    SAFE_ARC_RELEASE(_locationManager);
    SAFE_ARC_RELEASE(_locationManagerDelegate);
    SAFE_ARC_RELEASE(_propertyList);
    SAFE_ARC_RELEASE(_propertyListPath);

    SAFE_ARC_SUPER_DEALLOC();
}

/**
 * SetUserId: client explicitly initialized with a userId (can be nil).
 * If false, then attempt to load userId from saved eventsData.
 */
- (void)initializeWithEndpoint:(NSString*)endpointUrl withBuildName:(NSString*)buildName withKey:(NSString*)key withSecret:(NSString*)secret withUserId:(NSString*) userId {
    if (endpointUrl == nil) {
        NSLog(@"ERROR: endpointUrl cannot be nil in initializeWithEndpoint:");
        return;
    }
    
    if (buildName == nil) {
        NSLog(@"ERROR: buildName cannot be nil in initializeWithEndpoint:");
        return;
    }
    
    if (key == nil) {
        NSLog(@"ERROR: key cannot be nil in initializeWithEndpoint:");
        return;
    }

    if (secret == nil) {
        NSLog(@"ERROR: secret cannot be nil in initializeWithEndpoint:");
        return;
    }
    
    SAFE_ARC_RETAIN(key);
    SAFE_ARC_RELEASE(_apiKey);
    _apiKey = key;
    SAFE_ARC_RETAIN(secret);
    SAFE_ARC_RELEASE(_apiSecret);
    _apiSecret = secret;
    SAFE_ARC_RETAIN(endpointUrl);
    SAFE_ARC_RELEASE(_endpointUrl);
    _endpointUrl = endpointUrl;
    SAFE_ARC_RETAIN(buildName);
    SAFE_ARC_RELEASE(_buildName);
    _buildName = buildName;
    

    [self runOnBackgroundQueue:^{
        if (userId) {
            [self setUserId:userId];
        } else {
            _userId = SAFE_ARC_RETAIN([[TTDatabaseHelper getDatabaseHelper] getValue:USER_ID]);
        }
    }];

    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    if (state != UIApplicationStateBackground) {
        // If this is called while the app is running in the background, for example
        // via a push notification, don't call enterForeground
        [self enterForeground];
    }
    _initialized = YES;
    
}



/**
 * Run a block in the background. If already in the background, run immediately.
 */
- (BOOL)runOnBackgroundQueue:(void (^)(void))block
{
    if ([[NSOperationQueue currentQueue].name isEqualToString:BACKGROUND_QUEUE_NAME]) {
        TRAINTRACKS_LOG(@"Already running in the background.");
        block();
        return NO;
    }
    else {
        [_backgroundQueue addOperationWithBlock:block];
        return YES;
    }
}

#pragma mark - logEvent

- (void)logEvent:(NSString*) eventType
{
    [self logEvent:eventType withEventProperties:nil];
}

- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties
{
    [self logEvent:eventType withEventProperties:eventProperties outOfSession:NO];
}

- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties outOfSession:(BOOL) outOfSession
{
    [self logEvent:eventType withEventProperties:eventProperties withApiProperties:nil withUserProperties:nil withTimestamp:nil outOfSession:outOfSession];
}

- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties withApiProperties:(NSDictionary*) apiProperties withUserProperties:(NSDictionary*) userProperties withTimestamp:(NSNumber*) timestamp outOfSession:(BOOL) outOfSession
{
    if (_apiKey == nil) {
        NSLog(@"ERROR: apiKey cannot be nil or empty, set apiKey with initializeApiKey: before calling logEvent");
        return;
    }

    if (_apiSecret == nil) {
        NSLog(@"ERROR: apiSecret cannot be nil or empty, set apiSecret with initializeApiKey: before calling logEvent");
        return;
    }
    
    if (![self isArgument:eventType validType:[NSString class] methodName:@"logEvent"]) {
        return;
    }
    if (eventProperties != nil && ![self isArgument:eventProperties validType:[NSDictionary class] methodName:@"logEvent"]) {
        return;
    }

    if (timestamp == nil) {
        timestamp = [NSNumber numberWithLongLong:[[self currentTime] timeIntervalSince1970] * 1000];
    }

    // Create snapshot of all event json objects, to prevent deallocation crash
    eventProperties = [eventProperties copy];
    apiProperties = [apiProperties mutableCopy];
    userProperties = [userProperties copy];
    
    [self runOnBackgroundQueue:^{
        TTDatabaseHelper *dbHelper = [TTDatabaseHelper getDatabaseHelper];

        // Respect the opt-out setting by not sending or storing any events.
        if ([self optOut])  {
            NSLog(@"User has opted out of tracking. Event %@ not logged.", eventType);
            SAFE_ARC_RELEASE(eventProperties);
            SAFE_ARC_RELEASE(apiProperties);
            SAFE_ARC_RELEASE(userProperties);
            return;
        }

        // skip session check if logging start_session or end_session events
        BOOL loggingSessionEvent = _trackingSessionEvents && ([eventType isEqualToString:kTTSessionStartEvent] || [eventType isEqualToString:kTTSessionEndEvent]);
        if (!loggingSessionEvent && !outOfSession) {
            [self startOrContinueSession:timestamp];
        }
        
        NSMutableDictionary *rootEvent = [NSMutableDictionary dictionary];
        
        [rootEvent setValue:_buildName forKey:@"build"];

        NSString *clientTimestamp = [_dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[timestamp longLongValue]/1000]];
        
        [rootEvent setValue:clientTimestamp forKey:@"clientTimestamp"];
        [rootEvent setValue:_buildName forKey:@"build"];
        [rootEvent setValue:eventType forKey:@"eventType"];
        [rootEvent setValue:_userId forKey:@"userId"];
        
        if(_userName == nil) {
            [rootEvent setValue:_userId forKey:@"userName"];
        } else {
            [rootEvent setValue:_userName forKey:@"userName"];
        }

        [rootEvent setValue:_deviceInfo.osName forKey:@"device"];
        
        // TODO:
        // What to do about out of session
        [rootEvent setValue:[NSNumber numberWithLongLong:_sessionId] forKey:@"sessionId"];


        NSMutableDictionary *event = [NSMutableDictionary dictionary];
        [event setValue:eventType forKey:@"eventType"];
        [event setValue:[self replaceWithEmptyJSON:[self truncate:eventProperties]] forKey:@"eventProperties"];
        [event setValue:[self replaceWithEmptyJSON:apiProperties] forKey:@"apiProperties"];
        [event setValue:[self replaceWithEmptyJSON:[self truncate:userProperties]] forKey:@"userProperties"];
        [event setValue:[NSNumber numberWithLongLong:outOfSession ? -1 : _sessionId] forKey:@"sessionId"];
        [event setValue:timestamp forKey:@"timestamp"];

        SAFE_ARC_RELEASE(eventProperties);
        SAFE_ARC_RELEASE(apiProperties);
        SAFE_ARC_RELEASE(userProperties);

        [self annotateEvent:event];

        [rootEvent setValue:event forKey:@"data"];
        // convert event dictionary to JSON String
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rootEvent options:0 error:NULL];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSLog(@"rootevent: %@", jsonString);
        if ([eventType isEqualToString:IDENTIFY_EVENT]) {
            [dbHelper addIdentify:jsonString];
        } else {
            [dbHelper addEvent:jsonString];
        }
        SAFE_ARC_RELEASE(jsonString);

        TRAINTRACKS_LOG(@"Logged %@ Event", rootEvent[@"eventType"]);
        NSLog(@"Logged event: %@", jsonString);

        [self truncateEventQueues];

        int eventCount = [dbHelper getTotalEventCount]; // refetch since events may have been deleted
        if ((eventCount % self.eventUploadThreshold) == 0 && eventCount >= self.eventUploadThreshold) {
            [self uploadEvents];
        } else {
            [self uploadEventsWithDelay:self.eventUploadPeriodSeconds];
        }
    }];
}

- (void)truncateEventQueues
{
    TTDatabaseHelper *dbHelper = [TTDatabaseHelper getDatabaseHelper];
    int numEventsToRemove = MIN(MAX(1, self.eventMaxCount/10), kTTEventRemoveBatchSize);
    int eventCount = [dbHelper getEventCount];
    if (eventCount > self.eventMaxCount) {
        [dbHelper removeEvents:([dbHelper getNthEventId:numEventsToRemove])];
    }
    int identifyCount = [dbHelper getIdentifyCount];
    if (identifyCount > self.eventMaxCount) {
        [dbHelper removeIdentifys:([dbHelper getNthIdentifyId:numEventsToRemove])];
    }
}

- (void)annotateEvent:(NSMutableDictionary*) event
{
    [event setValue:_userId forKey:@"userId"];
    [event setValue:_deviceId forKey:@"deviceId"];
    [event setValue:kTTPlatform forKey:@"platform"];
    [event setValue:_deviceInfo.appVersion forKey:@"versionName"];
    [event setValue:_deviceInfo.osName forKey:@"osName"];
    [event setValue:_deviceInfo.osVersion forKey:@"osVersion"];
    [event setValue:_deviceInfo.model forKey:@"deviceModel"];
    [event setValue:_deviceInfo.manufacturer forKey:@"deviceManufacturer"];
    [event setValue:_deviceInfo.carrier forKey:@"carrier"];
    [event setValue:_deviceInfo.country forKey:@"country"];
    [event setValue:_deviceInfo.language forKey:@"language"];
    NSDictionary *library = @{
        @"name": kTTLibrary,
        @"version": kTTVersion
    };
    [event setValue:library forKey:@"library"];
    [event setValue:[TTUtils generateUUID] forKey:@"uuid"];
    [event setValue:[NSNumber numberWithLongLong:[self getNextSequenceNumber]] forKey:@"sequenceNumber"];

    NSMutableDictionary *apiProperties = [event valueForKey:@"apiProperties"];

    NSString* advertiserID = _deviceInfo.advertiserId;
    if (advertiserID) {
        [apiProperties setValue:advertiserID forKey:@"iosIdfa"];
    }
    NSString* vendorID = _deviceInfo.vendorId;
    if (vendorID) {
        [apiProperties setValue:vendorID forKey:@"iosIdfv"];
    }
    
    if (_lastKnownLocation != nil) {
        @synchronized (_locationManager) {
            NSMutableDictionary *location = [NSMutableDictionary dictionary];

            // Need to use NSInvocation because coordinate selector returns a C struct
            SEL coordinateSelector = NSSelectorFromString(@"coordinate");
            NSMethodSignature *coordinateMethodSignature = [_lastKnownLocation methodSignatureForSelector:coordinateSelector];
            NSInvocation *coordinateInvocation = [NSInvocation invocationWithMethodSignature:coordinateMethodSignature];
            [coordinateInvocation setTarget:_lastKnownLocation];
            [coordinateInvocation setSelector:coordinateSelector];
            [coordinateInvocation invoke];
            CLLocationCoordinate2D lastKnownLocationCoordinate;
            [coordinateInvocation getReturnValue:&lastKnownLocationCoordinate];

            [location setValue:[NSNumber numberWithDouble:lastKnownLocationCoordinate.latitude] forKey:@"lat"];
            [location setValue:[NSNumber numberWithDouble:lastKnownLocationCoordinate.longitude] forKey:@"lon"];

            [apiProperties setValue:location forKey:@"location"];
        }
    }
}


#pragma mark - Upload events

- (void)uploadEventsWithDelay:(int) delay
{
    if (!_updateScheduled) {
        _updateScheduled = YES;
        __block __weak Traintracks *weakSelf = self;
        [_backgroundQueue addOperationWithBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf performSelector:@selector(uploadEventsInBackground) withObject:nil afterDelay:delay];
            });
        }];
    }
}

- (void)uploadEventsInBackground
{
    _updateScheduled = NO;
    [self uploadEvents];
}

- (void)uploadEvents
{
    int limit = _backoffUpload ? _backoffUploadBatchSize : self.eventUploadMaxBatchSize;
    [self uploadEventsWithLimit:limit];
}

- (void)uploadEventsWithLimit:(int) limit
{
    if (_apiKey == nil) {
        NSLog(@"ERROR: apiKey cannot be nil or empty, set apiKey with initializeApiKey: before calling uploadEvents:");
        return;
    }

    @synchronized ([Traintracks class]) {
        if (_updatingCurrently) {
            return;
        }
        _updatingCurrently = YES;
    }
    
    [self runOnBackgroundQueue:^{

        // Don't communicate with the server if the user has opted out.
        if ([self optOut] || _offline)  {
            _updatingCurrently = NO;
            return;
        }

        TTDatabaseHelper *dbHelper = [TTDatabaseHelper getDatabaseHelper];
        long eventCount = [dbHelper getTotalEventCount];
        long numEvents = limit > 0 ? fminl(eventCount, limit) : eventCount;
        if (numEvents == 0) {
            _updatingCurrently = NO;
            return;
        }
        NSMutableArray *events = [dbHelper getEvents:-1 limit:numEvents];
        NSMutableArray *identifys = [dbHelper getIdentifys:-1 limit:numEvents];
        NSDictionary *merged = [self mergeEventsAndIdentifys:events identifys:identifys numEvents:numEvents];

        NSMutableArray *uploadEvents = [merged objectForKey:EVENTS];
        long long maxEventId = [[merged objectForKey:MAX_EVENT_ID] longLongValue];
        long long maxIdentifyId = [[merged objectForKey:MAX_IDENTIFY_ID] longLongValue];

        NSError *error = nil;
        NSData *eventsDataLocal = nil;
        @try {
            eventsDataLocal = [NSJSONSerialization dataWithJSONObject:[self makeJSONSerializable:uploadEvents] options:0 error:&error];
        }
        @catch (NSException *exception) {
            NSLog(@"ERROR: NSJSONSerialization error: %@", exception.reason);
            _updatingCurrently = NO;
            return;
        }
        if (error != nil) {
            NSLog(@"ERROR: NSJSONSerialization error: %@", error);
            _updatingCurrently = NO;
            return;
        }
        if (eventsDataLocal) {
            NSString *eventsString = [[NSString alloc] initWithData:eventsDataLocal encoding:NSUTF8StringEncoding];
            [self makeEventUploadPostRequest:_endpointUrl events:eventsString maxEventId:maxEventId maxIdentifyId:maxIdentifyId];
            SAFE_ARC_RELEASE(eventsString);
       }
    }];
}

- (long long)getNextSequenceNumber
{
    TTDatabaseHelper *dbHelper = [TTDatabaseHelper getDatabaseHelper];
    NSNumber *sequenceNumberFromDB = [dbHelper getLongValue:SEQUENCE_NUMBER];
    long long sequenceNumber = 0;
    if (sequenceNumberFromDB != nil) {
        sequenceNumber = [sequenceNumberFromDB longLongValue];
    }

    sequenceNumber++;
    [dbHelper insertOrReplaceKeyLongValue:SEQUENCE_NUMBER value:[NSNumber numberWithLongLong:sequenceNumber]];

    return sequenceNumber;
}

- (NSDictionary*)mergeEventsAndIdentifys:(NSMutableArray*)events identifys:(NSMutableArray*)identifys numEvents:(long) numEvents
{
    NSMutableArray *mergedEvents = [[NSMutableArray alloc] init];
    long long maxEventId = -1;
    long long maxIdentifyId = -1;

    // NSArrays actually have O(1) performance for push/pop
    while ([mergedEvents count] < numEvents) {
        NSDictionary *event = nil;
        NSDictionary *identify = nil;

        // case 1: no identifys grab from events
        if ([identifys count] == 0) {
            event = SAFE_ARC_RETAIN(events[0]);
            [events removeObjectAtIndex:0];
            maxEventId = [[event objectForKey:@"eventId"] longValue];

        // case 2: no events grab from identifys
        } else if ([events count] == 0) {
            identify = SAFE_ARC_RETAIN(identifys[0]);
            [identifys removeObjectAtIndex:0];
            maxIdentifyId = [[identify objectForKey:@"eventId"] longValue];

        // case 3: need to compare sequence numbers
        } else {
            // events logged before v3.2.0 won't have sequeunce number, put those first
            event = SAFE_ARC_RETAIN(events[0]);
            identify = SAFE_ARC_RETAIN(identifys[0]);
            if ([event objectForKey:SEQUENCE_NUMBER] == nil ||
                    ([[event objectForKey:SEQUENCE_NUMBER] longLongValue] <
                     [[identify objectForKey:SEQUENCE_NUMBER] longLongValue])) {
                [events removeObjectAtIndex:0];
                maxEventId = [[event objectForKey:EVENT_ID] longValue];
                SAFE_ARC_RELEASE(identify);
                identify = nil;
            } else {
                [identifys removeObjectAtIndex:0];
                maxIdentifyId = [[identify objectForKey:EVENT_ID] longValue];
                SAFE_ARC_RELEASE(event);
                event = nil;
            }
        }

        [mergedEvents addObject: event != nil ? event : identify];
        SAFE_ARC_RELEASE(event);
        SAFE_ARC_RELEASE(identify);
    }

    NSDictionary *results = [[NSDictionary alloc] initWithObjectsAndKeys: mergedEvents, EVENTS, [NSNumber numberWithLongLong:maxEventId], MAX_EVENT_ID, [NSNumber numberWithLongLong:maxIdentifyId], MAX_IDENTIFY_ID, nil];
    SAFE_ARC_RELEASE(mergedEvents);
    return SAFE_ARC_AUTORELEASE(results);
}

- (void)makeEventUploadPostRequest:(NSString*) url events:(NSString*) events maxEventId:(long long) maxEventId maxIdentifyId:(long long) maxIdentifyId
{
    NSMutableURLRequest *request =[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setTimeoutInterval:60.0];
    [request setHTTPMethod:@"POST"];
    
    // Header
    NSString *checksumData = [NSString stringWithFormat:@"%@%@", events, _apiSecret];
    NSString *checksum = [self md5HexDigest: checksumData];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:_apiKey forHTTPHeaderField:@"X-Product-Key"];
    [request setValue:[NSString stringWithFormat:@"%@", checksum] forHTTPHeaderField:@"X-Product-Auth"];
    [request setValue:@"1.2.3.4" forHTTPHeaderField:@"Remote-Address"];
    
    // Body
    NSMutableData *postData = [[NSMutableData alloc] init];
    [postData appendData:[events dataUsingEncoding:NSUTF8StringEncoding]];

    [request setHTTPBody:postData];


    NSLog(@"URL: %@", [request URL]);
    NSLog(@"HEADERS: %@", [request allHTTPHeaderFields]);
    SAFE_ARC_RELEASE(postData);

    NSLog(@"BODY: %@", [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding]);

    id Connection = [NSURLConnection class];
    [Connection sendAsynchronousRequest:request queue:_backgroundQueue completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        TTDatabaseHelper *dbHelper = [TTDatabaseHelper getDatabaseHelper];
        BOOL uploadSuccessful = NO;
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (response != nil) {
            if ([httpResponse statusCode] == 200) {
                // success, remove existing events from dictionary
                uploadSuccessful = YES;
                if (maxEventId >= 0) {
                    [dbHelper removeEvents:maxEventId];
                }
                if (maxIdentifyId >= 0) {
                    [dbHelper removeIdentifys:maxIdentifyId];
                }
                NSLog(@"server response: %@", result);
            } else if ([httpResponse statusCode] == 413) {
                // If blocked by one massive event, drop it
                if (_backoffUpload && _backoffUploadBatchSize == 1) {
                    if (maxEventId >= 0) {
                        [dbHelper removeEvent: maxEventId];
                    }
                    if (maxIdentifyId >= 0) {
                        [dbHelper removeIdentifys: maxIdentifyId];
                    }
                }

                // server complained about length of request, backoff and try again
                _backoffUpload = YES;
                int numEvents = fminl([dbHelper getEventCount], _backoffUploadBatchSize);
                _backoffUploadBatchSize = (int)ceilf(numEvents / 2.0f);
                TRAINTRACKS_LOG(@"Request too large, will decrease size and attempt to reupload");
                _updatingCurrently = NO;
                [self uploadEventsWithLimit:_backoffUploadBatchSize];

            } else {
                NSLog(@"ERROR: Connection response received:%ld, %@", (long)[httpResponse statusCode], result);
            }
        } else if (error != nil) {
            if ([error code] == -1009) {
                TRAINTRACKS_LOG(@"No internet connection (not connected to internet), unable to upload events");
            } else if ([error code] == -1003) {
                TRAINTRACKS_LOG(@"No internet connection (hostname not found), unable to upload events");
            } else if ([error code] == -1001) {
                TRAINTRACKS_LOG(@"No internet connection (request timed out), unable to upload events");
            } else {
                NSLog(@"ERROR: Connection error:%@", error);
            }
        } else {
            NSLog(@"ERROR: response empty, error empty for NSURLConnection");
        }

        NSLog(@"Server responded: %@", result);
        SAFE_ARC_RELEASE(result);
        _updatingCurrently = NO;

        if (uploadSuccessful && [dbHelper getEventCount] > self.eventUploadThreshold) {
            int limit = _backoffUpload ? _backoffUploadBatchSize : 0;
            [self uploadEventsWithLimit:limit];

        } else if (_uploadTaskID != UIBackgroundTaskInvalid) {
            if (uploadSuccessful) {
                _backoffUpload = NO;
                _backoffUploadBatchSize = self.eventUploadMaxBatchSize;
            }

            // Upload finished, allow background task to be ended
            [[UIApplication sharedApplication] endBackgroundTask:_uploadTaskID];
            _uploadTaskID = UIBackgroundTaskInvalid;
        }
    }];
}

#pragma mark - application lifecycle methods

- (void)enterForeground
{
    [self updateLocation];

    NSNumber* now = [NSNumber numberWithLongLong:[[self currentTime] timeIntervalSince1970] * 1000];

    // Stop uploading
    if (_uploadTaskID != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_uploadTaskID];
        _uploadTaskID = UIBackgroundTaskInvalid;
    }
    [self runOnBackgroundQueue:^{
        [self startOrContinueSession:now];
        _inForeground = YES;
        [self uploadEvents];
    }];
}

- (void)enterBackground
{
    NSNumber* now = [NSNumber numberWithLongLong:[[self currentTime] timeIntervalSince1970] * 1000];

    // Stop uploading
    if (_uploadTaskID != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_uploadTaskID];
    }
    _uploadTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        //Took too long, manually stop
        if (_uploadTaskID != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:_uploadTaskID];
            _uploadTaskID = UIBackgroundTaskInvalid;
        }
    }];
    [self runOnBackgroundQueue:^{
        _inForeground = NO;
        [self refreshSessionTime:now];
        [self uploadEventsWithLimit:0];
    }];
}

#pragma mark - Sessions

/**
 * Creates a new session if we are in the background and
 * the current session is expired or if there is no current session ID].
 * Otherwise extends the session.
 *
 * Returns true of a new session was created.
 */
- (BOOL)startOrContinueSession:(NSNumber*) timestamp
{
    if (!_inForeground) {
        if ([self inSession]) {
            if ([self isWithinMinTimeBetweenSessions:timestamp]) {
                [self refreshSessionTime:timestamp];
                return FALSE;
            }
            [self startNewSession:timestamp];
            return TRUE;
        }
        // no current session, check for previous session
        if ([self isWithinMinTimeBetweenSessions:timestamp]) {
            // extract session id
            long long previousSessionId = [self previousSessionId];
            if (previousSessionId == -1) {
                [self startNewSession:timestamp];
                return TRUE;
            }
            // extend previous session
            [self setSessionId:previousSessionId];
            [self refreshSessionTime:timestamp];
            return FALSE;
        } else {
            [self startNewSession:timestamp];
            return TRUE;
        }
    }
    // not creating a session means we should continue the session
    [self refreshSessionTime:timestamp];
    return FALSE;
}

- (void)startNewSession:(NSNumber*) timestamp
{
    if (_trackingSessionEvents) {
        [self sendSessionEvent:kTTSessionEndEvent];
    }
    [self setSessionId:[timestamp longLongValue]];
    [self refreshSessionTime:timestamp];
    if (_trackingSessionEvents) {
        [self sendSessionEvent:kTTSessionStartEvent];
    }
}

- (void)sendSessionEvent:(NSString*) sessionEvent
{
    if (_apiKey == nil) {
        NSLog(@"ERROR: apiKey cannot be nil or empty, set apiKey with initializeApiKey: before sending session event");
        return;
    }

    if (![self inSession]) {
        return;
    }

    NSMutableDictionary *apiProperties = [NSMutableDictionary dictionary];
    [apiProperties setValue:sessionEvent forKey:@"special"];
    NSNumber* timestamp = [self lastEventTime];
    [self logEvent:sessionEvent withEventProperties:nil withApiProperties:apiProperties withUserProperties:nil withTimestamp:timestamp outOfSession:NO];
}

- (BOOL)inSession
{
    return _sessionId >= 0;
}

- (BOOL)isWithinMinTimeBetweenSessions:(NSNumber*) timestamp
{
    NSNumber *previousSessionTime = [self lastEventTime];
    long long timeDelta = [timestamp longLongValue] - [previousSessionTime longLongValue];

    return timeDelta < self.minTimeBetweenSessionsMillis;
}

/**
 * Sets the session ID in memory and persists it to disk.
 */
- (void)setSessionId:(long long) timestamp
{
    _sessionId = timestamp;
    [self setPreviousSessionId:_sessionId];
}

/**
 * Update the session timer if there's a running session.
 */
- (void)refreshSessionTime:(NSNumber*) timestamp
{
    if (![self inSession]) {
        return;
    }
    [self setLastEventTime:timestamp];
}

- (void)setPreviousSessionId:(long long) previousSessionId
{
    NSNumber *value = [NSNumber numberWithLongLong:previousSessionId];
    [[TTDatabaseHelper getDatabaseHelper] insertOrReplaceKeyLongValue:PREVIOUS_SESSION_ID value:value];
}

- (long long)previousSessionId
{
    NSNumber* previousSessionId = [[TTDatabaseHelper getDatabaseHelper] getLongValue:PREVIOUS_SESSION_ID];
    if (previousSessionId == nil) {
        return -1;
    }
    return [previousSessionId longLongValue];
}

- (void)setLastEventTime:(NSNumber*) timestamp
{
    [[TTDatabaseHelper getDatabaseHelper] insertOrReplaceKeyLongValue:PREVIOUS_SESSION_TIME value:timestamp];
}

- (NSNumber*)lastEventTime
{
    return [[TTDatabaseHelper getDatabaseHelper] getLongValue:PREVIOUS_SESSION_TIME];
}

- (void)startSession
{
    return;
}

- (void)identify:(TTIdentify *)identify
{
    if (identify == nil || [identify.userPropertyOperations count] == 0) {
        return;
    }
    [self logEvent:IDENTIFY_EVENT withEventProperties:nil withApiProperties:nil withUserProperties:identify.userPropertyOperations withTimestamp:nil outOfSession:NO];
}

#pragma mark - configurations

- (void)setUserProperties:(NSDictionary*) userProperties
{
    if (userProperties == nil || ![self isArgument:userProperties validType:[NSDictionary class] methodName:@"setUserProperties:"] || [userProperties count] == 0) {
        return;
    }

    NSDictionary *copy = [userProperties copy];
    [self runOnBackgroundQueue:^{
        TTIdentify *identify = [TTIdentify identify];
        for (NSString *key in copy) {
            NSObject *value = [copy objectForKey:key];
            [identify set:key value:value];
        }
        [self identify:identify];
    }];
}

// maintain for legacy
- (void)setUserProperties:(NSDictionary*) userProperties replace:(BOOL) replace
{
    [self setUserProperties:userProperties];
}

- (void)setUserId:(NSString*) userId
{
    if (!(userId == nil || [self isArgument:userId validType:[NSString class] methodName:@"setUserId:"])) {
        return;
    }
    
    [self runOnBackgroundQueue:^{
        SAFE_ARC_RETAIN(userId);
        SAFE_ARC_RELEASE(_userId);
        _userId = userId;
        [[TTDatabaseHelper getDatabaseHelper] insertOrReplaceKeyValue:USER_ID value:_userId];
    }];
}

- (void)setUserName:(NSString*) userName
{
    if (!(userName == nil || [self isArgument:userName validType:[NSString class] methodName:@"setUserName:"])) {
        return;
    }
    
    [self runOnBackgroundQueue:^{
        SAFE_ARC_RETAIN(userName);
        SAFE_ARC_RELEASE(_userName);
        _userName = userName;
        [[TTDatabaseHelper getDatabaseHelper] insertOrReplaceKeyValue:USER_NAME value:_userName];
    }];
}

- (void)setOptOut:(BOOL)enabled
{
    [self runOnBackgroundQueue:^{
        NSNumber *value = [NSNumber numberWithBool:enabled];
        [[TTDatabaseHelper getDatabaseHelper] insertOrReplaceKeyLongValue:OPT_OUT value:value];
    }];
}

- (void)setOffline:(BOOL)offline
{
    _offline = offline;

    if (!_offline) {
        [self uploadEvents];
    }
}

- (void)setEventUploadMaxBatchSize:(int) eventUploadMaxBatchSize
{
    _eventUploadMaxBatchSize = eventUploadMaxBatchSize;
    _backoffUploadBatchSize = eventUploadMaxBatchSize;
}

- (BOOL)optOut
{
    return [[[TTDatabaseHelper getDatabaseHelper] getLongValue:OPT_OUT] boolValue];
}

- (void)setDeviceId:(NSString*)deviceId
{
    if (![self isValidDeviceId:deviceId]) {
        return;
    }

    [self runOnBackgroundQueue:^{
        SAFE_ARC_RETAIN(deviceId);
        SAFE_ARC_RELEASE(_deviceId);
        _deviceId = deviceId;
        [[TTDatabaseHelper getDatabaseHelper] insertOrReplaceKeyValue:DEVICE_ID value:deviceId];
    }];
}

#pragma mark - location methods

- (void)updateLocation
{
    if (_locationListeningEnabled) {
        CLLocation *location = [_locationManager location];
        @synchronized (_locationManager) {
            if (location != nil) {
                (void) SAFE_ARC_RETAIN(location);
                SAFE_ARC_RELEASE(_lastKnownLocation);
                _lastKnownLocation = location;
            }
        }
    }
}

- (void)enableLocationListening
{
    _locationListeningEnabled = YES;
    [self updateLocation];
}

- (void)disableLocationListening
{
    _locationListeningEnabled = NO;
}

- (void)useAdvertisingIdForDeviceId
{
    _useAdvertisingIdForDeviceId = YES;
}

#pragma mark - Getters for device data
- (NSString*) getDeviceId
{
    return _deviceId;
}

- (NSString*) initializeDeviceId
{
    if (_deviceId == nil) {
        TTDatabaseHelper *dbHelper = [TTDatabaseHelper getDatabaseHelper];
        _deviceId = SAFE_ARC_RETAIN([dbHelper getValue:DEVICE_ID]);
        if (![self isValidDeviceId:_deviceId]) {
            NSString *newDeviceId = SAFE_ARC_RETAIN([self _getDeviceId]);
            SAFE_ARC_RELEASE(_deviceId);
            _deviceId = newDeviceId;
            [dbHelper insertOrReplaceKeyValue:DEVICE_ID value:newDeviceId];
        }
    }
    return _deviceId;
}

- (NSString*)_getDeviceId
{
    NSString *deviceId = nil;
    if (_useAdvertisingIdForDeviceId) {
        deviceId = _deviceInfo.advertiserId;
    }

    // return identifierForVendor
    if (!deviceId) {
        deviceId = _deviceInfo.vendorId;
    }

    if (!deviceId) {
        // Otherwise generate random ID
        deviceId = _deviceInfo.generateUUID;
    }
    return SAFE_ARC_AUTORELEASE([[NSString alloc] initWithString:deviceId]);
}

- (BOOL)isValidDeviceId:(NSString*)deviceId
{
    if (deviceId == nil ||
        ![self isArgument:deviceId validType:[NSString class] methodName:@"isValidDeviceId"] ||
        [deviceId isEqualToString:@"e3f5536a141811db40efd6400f1d0a4e"] ||
        [deviceId isEqualToString:@"04bab7ee75b9a58d39b8dc54e8851084"]) {
        return NO;
    }
    return YES;
}

- (NSDictionary*)replaceWithEmptyJSON:(NSDictionary*) dictionary
{
    return dictionary == nil ? [NSMutableDictionary dictionary] : dictionary;
}

- (id) truncate:(id) obj
{
    if ([obj isKindOfClass:[NSString class]]) {
        obj = (NSString*)obj;
        if ([obj length] > kTTMaxStringLength) {
            obj = [obj substringToIndex:kTTMaxStringLength];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [NSMutableArray array];
        id objCopy = [obj copy];
        for (id i in objCopy) {
            [arr addObject:[self truncate:i]];
        }
        SAFE_ARC_RELEASE(objCopy);
        obj = [NSArray arrayWithArray:arr];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        id objCopy = [obj copy];
        for (id key in objCopy) {
            NSString *coercedKey;
            if (![key isKindOfClass:[NSString class]]) {
                coercedKey = [key description];
                NSLog(@"WARNING: Non-string property key, received %@, coercing to %@", [key class], coercedKey);
            } else {
                coercedKey = key;
            }
            dict[coercedKey] = [self truncate:objCopy[key]];
        }
        SAFE_ARC_RELEASE(objCopy);
        obj = [NSDictionary dictionaryWithDictionary:dict];
    }
    return obj;
}

- (id) makeJSONSerializable:(id) obj
{
    if (obj == nil) {
        return [NSNull null];
    }
    if ([obj isKindOfClass:[NSString class]] ||
        [obj isKindOfClass:[NSNull class]]) {
        return obj;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (!isfinite([obj floatValue])) {
            return [NSNull null];
        } else {
            return obj;
        }
    }
    if ([obj isKindOfClass:[NSDate class]]) {
        return [obj description];
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [NSMutableArray array];
        id objCopy = [obj copy];
        for (id i in objCopy) {
            [arr addObject:[self makeJSONSerializable:i]];
        }
        SAFE_ARC_RELEASE(objCopy);
        return [NSArray arrayWithArray:arr];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        id objCopy = [obj copy];
        for (id key in objCopy) {
            NSString *coercedKey;
            if (![key isKindOfClass:[NSString class]]) {
                coercedKey = [key description];
                NSLog(@"WARNING: Non-string property key, received %@, coercing to %@", [key class], coercedKey);
            } else {
                coercedKey = key;
            }
            dict[coercedKey] = [self makeJSONSerializable:objCopy[key]];
        }
        SAFE_ARC_RELEASE(objCopy);
        return [NSDictionary dictionaryWithDictionary:dict];
    }
    NSString *str = [obj description];
    NSLog(@"WARNING: Invalid property value type, received %@, coercing to %@", [obj class], str);
    return str;
}


- (BOOL)isArgument:(id) argument validType:(Class) class methodName:(NSString*) methodName
{
    if ([argument isKindOfClass:class]) {
        return YES;
    } else {
        NSLog(@"ERROR: Invalid type argument to method %@, expected %@, received %@, ", methodName, class, [argument class]);
        return NO;
    }
}

- (NSString*)md5HexDigest:(NSString*)input
{
    const char* str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG) strlen(str), result);

    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

- (NSString*)urlEncodeString:(NSString*) string
{
    NSString *newString;
#if __has_feature(objc_arc)
    newString = (__bridge_transfer NSString*)
    CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                            (__bridge CFStringRef)string,
                                            NULL,
                                            CFSTR(":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`"),
                                            CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
#else
    newString = NSMakeCollectable(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                          (CFStringRef)string,
                                                                          NULL,
                                                                          CFSTR(":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`"),
                                                                          CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding)));
    SAFE_ARC_AUTORELEASE(newString);
#endif
    if (newString) {
        return newString;
    }
    return @"";
}

- (NSDate*) currentTime
{
    return [NSDate date];
}

- (void)printEventsCount
{
    NSLog(@"Events count:%ld", (long) [[TTDatabaseHelper getDatabaseHelper] getEventCount]);
}


#pragma mark - Filesystem

- (BOOL)savePropertyList {
    @synchronized (_propertyList) {
        BOOL success = [self serializePList:_propertyList toFile:_propertyListPath];
        if (!success) {
            NSLog(@"Error: Unable to save propertyList to file");
        }
        return success;
    }
}

- (id)deserializePList:(NSString*)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSData *pListData = [[NSFileManager defaultManager] contentsAtPath:path];
        if (pListData != nil) {
            NSError *error = nil;
            NSMutableDictionary *pList = (NSMutableDictionary *)[NSPropertyListSerialization
                                                                   propertyListWithData:pListData
                                                                   options:NSPropertyListMutableContainersAndLeaves
                                                                   format:NULL error:&error];
            if (error == nil) {
                return pList;
            } else {
                NSLog(@"ERROR: propertyList deserialization error:%@", error);
                error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
                if (error != nil) {
                    NSLog(@"ERROR: Can't remove corrupt propertyList file:%@", error);
                }
            }
        }
    }
    return nil;
}

- (BOOL)serializePList:(id)data toFile:(NSString*)path {
    NSError *error = nil;
    NSData *propertyListData = [NSPropertyListSerialization
                                dataWithPropertyList:data
                                format:NSPropertyListXMLFormat_v1_0
                                options:0 error:&error];
    if (error == nil) {
        if (propertyListData != nil) {
            BOOL success = [propertyListData writeToFile:path atomically:YES];
            if (!success) {
                NSLog(@"ERROR: Unable to save propertyList to file");
            }
            return success;
        } else {
            NSLog(@"ERROR: propertyListData is nil");
        }
    } else {
        NSLog(@"ERROR: Unable to serialize propertyList:%@", error);
    }
    return FALSE;

}

- (id)unarchive:(NSString*)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            id data = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
            return data;
        }
        @catch (NSException *e) {
            NSLog(@"EXCEPTION: Corrupt file %@: %@", [e name], [e reason]);
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
            if (error != nil) {
                NSLog(@"ERROR: Can't remove corrupt archiveDict file:%@", error);
            }
        }
    }
    return nil;
}

- (BOOL)archive:(id) obj toFile:(NSString*)path {
    return [NSKeyedArchiver archiveRootObject:obj toFile:path];
}

- (BOOL)moveFileIfNotExists:(NSString*)from to:(NSString*)to
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    if (![fileManager fileExistsAtPath:to] &&
        [fileManager fileExistsAtPath:from]) {
        if ([fileManager copyItemAtPath:from toPath:to error:&error]) {
            TRAINTRACKS_LOG(@"INFO: copied %@ to %@", from, to);
            [fileManager removeItemAtPath:from error:NULL];
        } else {
            TRAINTRACKS_LOG(@"WARN: Copy from %@ to %@ failed: %@", from, to, error);
            return false;
        }
    }
    return true;
}

@end
