//
// Traintracks.h
//
#import <Foundation/Foundation.h>
#import "TTIdentify.h"


/*
 Traintracks API.
 */
@interface Traintracks : NSObject

#pragma mark - Properties
@property (nonatomic, strong, readonly) NSString *endpointUrl;
@property (nonatomic, strong, readonly) NSString *buildName;
@property (nonatomic, strong, readonly) NSString *apiKey;
@property (nonatomic, strong, readonly) NSString *apiSecret;
@property (nonatomic, strong, readonly) NSString *userId;
@property (nonatomic, strong, readonly) NSString *userName;
@property (nonatomic, strong, readonly) NSString *deviceId;
@property (nonatomic, assign) BOOL optOut;

/*!
 The maximum number of events that can be stored locally before forcing an upload.
 The default is 30 events.
 */
@property (nonatomic, assign) int eventUploadThreshold;

/*!
 The maximum number of events that can be uploaded in a single request.
 The default is 100 events.
 */
@property (nonatomic, assign) int eventUploadMaxBatchSize;

/*!
 The maximum number of events that can be stored lcoally.
 The default is 1000 events.
 */
@property (nonatomic, assign) int eventMaxCount;

/*!
 The amount of time after an event is logged that events will be batched before being uploaded to the server.
 The default is 30 seconds.
 */
@property (nonatomic, assign) int eventUploadPeriodSeconds;

/*!
 When a user closes and reopens the app within minTimeBetweenSessionsMillis milliseconds, the reopen is considered part of the same session and the session continues. Otherwise, a new session is created.
 The default is 15 minutes.
 */
@property (nonatomic, assign) long minTimeBetweenSessionsMillis;

/*!
 Whether to track start and end of session events
 */
@property (nonatomic, assign) BOOL trackingSessionEvents;


#pragma mark - Methods

+ (Traintracks*)instance;

- (void)initializeWithEndpoint:(NSString*)endpointUrl withBuildName:(NSString*)buildName withKey:(NSString*)key withSecret:(NSString*)secret withUserId:(NSString*) userId;

/*!
 @method

 @abstract
 Tracks an event

 @param eventType                The name of the event you wish to track.
 @param eventProperties          You can attach additional data to any event by passing a NSDictionary object.
 @param outOfSession             If YES, will track the event as out of session. Useful for push notification events.
 */
- (void)logEvent:(NSString*) eventType;
- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties;
- (void)logEvent:(NSString*) eventType withEventProperties:(NSDictionary*) eventProperties outOfSession:(BOOL) outOfSession;


/*!
 @method

 @abstract
 Update user properties using operations provided via Identify API.

 @param identify                   An TTIdentify object with the intended user property operations

 @discussion
 To update user properties, first create an TTIdentify object. For example if you wanted to set a user's gender, and then increment their
 karma count by 1, you would do:
 TTIdentify *identify = [[[TTIdentify identify] set:@"gender" value:@"male"] add:@"karma" value:[NSNumber numberWithInt:1]];
 Then you would pass this TTIdentify object to the identify function to send to the server: [[Traintracks instance] identify:identify];
 The Identify API supports add, set, setOnce, unset operations. See the TraintracksIdentify.h header file for the method signatures.
 */

- (void)identify:(TTIdentify *)identify;

/*!
 @method

 @abstract
 Manually forces the class to immediately upload all queued events.

 @discussion
 Events are saved locally. Uploads are batched to occur every 30 events and every 30 seconds, as well as on app close.
 Use this method to force the class to immediately upload all queued events.
 */
- (void)uploadEvents;

/*!
 @method

 @abstract
 Adds properties that are tracked on the user level.

 @param userProperties          An NSDictionary containing any additional data to be tracked.

 @discussion
 Property keys must be <code>NSString</code> objects and values must be serializable.
 */

- (void)setUserProperties:(NSDictionary*) userProperties;
- (void)setUserProperties:(NSDictionary*) userProperties replace:(BOOL) replace;

/*!
 @method

 @abstract
 Sets the userId.

 @param userId                  If your app has its own login system that you want to track users with, you can set the userId.

 @discussion
 If your app has its own login system that you want to track users with, you can set the userId.
 */
- (void)setUserId:(NSString*) userId;
- (void)setUserName:(NSString*) userName;

/*!
 @method

 @abstract
 Sets the deviceId.

 @param deviceId                  If your app has its own system for tracking devices, you can set the deviceId.

 @discussion
 If your app has its own system for tracking devices, you can set the deviceId.
 */
- (void)setDeviceId:(NSString*) deviceId;

/*!
 @method

 @abstract
 Enables tracking opt out.

 @param enabled                  Whether tracking opt out should be enabled or disabled.

 @discussion
 If the user wants to opt out of all tracking, use this method to enable opt out for them. Once opt out is enabled, no events will be saved locally or sent to the server. Calling this method again with enabled set to false will turn tracking back on for the user.
 */
- (void)setOptOut:(BOOL)enabled;

/*!
 @method

 @abstract
 Disables sending logged events to Traintracks servers.

 @param offline                  Whether logged events should be sent to Traintracks servers.

 @discussion
 If you want to stop logged events from being sent to Traintracks severs, use this method to set the client to offline. Once offline is enabled, logged events will not be sent to the server until offline is disabled. Calling this method again with offline set to false will allow events to be sent to server
     and the client will attempt to send events that have been queued while offline.
 */
- (void)setOffline:(BOOL)offline;

/*!
 @method

 @abstract
 Enables location tracking.

 @discussion
 If the user has granted your app location permissions, the SDK will also grab the location of the user.
 Traintracks will never prompt the user for location permissions itself, this must be done by your app.
 */
- (void)enableLocationListening;

/*!
 @method

 @abstract
 Disables location tracking.

 @discussion
 If you want location tracking disabled on startup of the app, call disableLocationListening before you call initializeApiKey.
 */
- (void)disableLocationListening;

/*!
 @method

 @abstract
 Uses advertisingIdentifier instead of identifierForVendor as the device ID

 @discussion
 Apple prohibits the use of advertisingIdentifier if your app does not have advertising. Useful for tying together data from advertising campaigns to anlaytics data. Must be called before initializeApiKey: is called to function.
 */
- (void)useAdvertisingIdForDeviceId;

/*!
 @method

 @abstract
 Prints the number of events in the queue.

 @discussion
 Debugging method to find out how many events are being stored locally on the device.
 */
- (void)printEventsCount;

/*!
 @method

 @abstract
 Returns deviceId

 @discussion
 The deviceId is an identifier used by Traintracks to determine unique users when no userId has been set.
 */
- (NSString*)getDeviceId;

#pragma mark - constants

extern NSString *const kTTSessionStartEvent;
extern NSString *const kTTSessionEndEvent;
extern NSString *const kTTRevenueEvent;

@end
