# ios-sdk-example

This is an example project on how to use the iOS SDK.

The application is based on [https://github.com/fullstackio/FlappySwift] and records events as one uses the application and sends them to Traintracks.

# Setup with CocoaPods 
Add this to your podfile
```
pod 'Traintracks', :git => 'https://github.com/traintracks/ios-sdk.git'
```

In every file that uses analytics, import Traintracks.h at the top:
 ``` swift 
import Traintracks
 ```

In the application:didFinishLaunchingWithOptions: method of your YourAppNameAppDelegate.m file, initialize the SDK:
 ``` swift 
 Traintracks.instance().initializeWithEndpoint("YOUR_API_ENDPOINT_HERE",
         withBuildName: "YOUR_VERSION_NAME_HERE",
         withKey: "YOUR_API_KEY_HERE",
         withSecret: "YOUR_API_SECRET_HERE",
         withUserId: "YOUR_USER_ID_HERE")
 ```

To track an event anywhere in the app, call:
 ``` swift 
 Traintracks.instance().logEvent("EVENT_NAME")
 ```

Events are saved locally. Uploads are batched to occur every 30 events and every 30 seconds, as well as on app close. After calling logEvent in your app, you will immediately see data appear on the Traintracks Website.

# Tracking Events #

It's important to think about what types of events you care about as a developer. You should aim to track between 20 and 200 types of events within your app. Common event types are different screens within the app, actions the user initiates (such as pressing a button), and events you want the user to complete (such as filling out a form, completing a level, or making a payment). Contact us if you want assistance determining what would be best for you to track.

# Tracking Sessions #

A session is a period of time that a user has the app in the foreground. Sessions within 5 minutes of each other are merged into a single session. In the iOS SDK, sessions are tracked automatically. When the SDK is initialized, it determines whether the app is launched into the foreground or background and starts a new session if launched in the foreground. A new session is created when the app comes back into the foreground after being out of the foreground for 5 minutes or more.

You can adjust the time window for which sessions are extended by changing the variable minTimeBetweenSessionsMillis:
``` objective-c
[Traintracks instance].minTimeBetweenSessionsMillis = 30 * 60 * 1000; // 30 minutes
```

By default start and end session events are not sent. To enable add this line before initializing the SDK:
``` objective-c
[[Traintracks instance] trackingSessionEvents:YES];
```

You can also log events as out of session. Out of session events have a session_id of -1 and are not considered part of the current session, meaning they do not extend the current session. You can log events as out of session by setting input parameter outOfSession to true when calling logEvent.

``` objective-c
[[Traintracks instance] logEvent:@"EVENT_IDENTIFIER_HERE" withEventProperties:nil outOfSession:true];
```

# Setting Event Properties #

You can attach additional data to any event by passing a NSDictionary object as the second argument to logEvent:withEventProperties:

``` objective-c
NSMutableDictionary *eventProperties = [NSMutableDictionary dictionary];
[eventProperties setValue:@"VALUE_GOES_HERE" forKey:@"KEY_GOES_HERE"];
[[Traintracks instance] logEvent:@"Compute Hash" withEventProperties:eventProperties];
```

# Setting User Properties

To add properties that are associated with a user, you can set user properties:

``` objective-c
NSMutableDictionary *userProperties = [NSMutableDictionary dictionary];
[userProperties setValue:@"VALUE_GOES_HERE" forKey:@"KEY_GOES_HERE"];
[[Traintracks instance] setUserProperties:userProperties];
```

To replace any existing user properties with a new set:

``` objective-c
NSMutableDictionary *userProperties = [NSMutableDictionary dictionary];
[userProperties setValue:@"VALUE_GOES_HERE" forKey:@"KEY_GOES_HERE"];
[[Traintracks instance] setUserProperties:userProperties replace:YES];
```

# User Property Operations #

The SDK supports the operations set, setOnce, unset, and add on individual user properties. The operations are declared via a provided `TTIdentify` interface. Multiple operations can be chained together in a single `TTIdentify` object. The `TTIdentify` object is then passed to the Traintracks client to send to the server. The results of the operations will be visible immediately in the dashboard, and take effect for events logged after. Note, each
operation on the `TTIdentify` object returns the same instance, allowing you to chain multiple operations together.

1. `set`: this sets the value of a user property.

    ``` objective-c
    TTIdentify *identify = [[[TTIdentify identify] set:@"gender" value:@"female"] set:@"age" value:[NSNumber numberForInt:20]];
    [[Traintracks instance] identify:identify];
    ```

2. `setOnce`: this sets the value of a user property only once. Subsequent `setOnce` operations on that user property will be ignored. In the following example, `sign_up_date` will be set once to `08/24/2015`, and the following setOnce to `09/14/2015` will be ignored:

    ``` objective-c
    TTIdentify *identify1 = [[TTIdentify identify] setOnce:@"sign_up_date" value:@"09/06/2015"];
    [[Traintracks instance] identify:identify1];

    TTIdentify *identify2 = [[TTIdentify identify] setOnce:@"sign_up_date" value:@"10/06/2015"];
    [[Traintracks instance] identify:identify2];
    ```

3. `unset`: this will unset and remove a user property.

    ``` objective-c
    TTIdentify *identify = [[[TTIdentify identify] unset:@"gender"] unset:@"age"];
    [[Traintracks instance] identify:identify];
    ```

4. `add`: this will increment a user property by some numerical value. If the user property does not have a value set yet, it will be initialized to 0 before being incremented.

    ``` objective-c
    TTIdentify *identify = [[[TTIdentify identify] add:@"karma" value:[NSNumber numberWithFloat:0.123]] add:@"friends" value:[NSNumber numberWithInt:1]];
    [[Traintracks instance] identify:identify];
    ```

Note: if a user property is used in multiple operations on the same `Identify` object, only the first operation will be saved, and the rest will be ignored. In this example, only the set operation will be saved, and the add and unset will be ignored:

```objective-c
TTIdentify *identify = [[[[TTIdentify identify] set:@"karma" value:[NSNumber numberWithInt:10]] add:@"friends" value:[NSNumber numberWithInt:1]] unset:@"karma"];
    [[Traintracks instance] identify:identify];
```

# Allowing Users to Opt Out

To stop all event and session logging for a user, call setOptOut:

``` objective-c
[[Traintracks instance] setOptOut:YES];
```

Logging can be restarted by calling setOptOut again with enabled set to NO.
No events will be logged during any period opt out is enabled, even after opt
out is disabled.

# Swift #

This SDK will work with Swift. If you are copying the source files or using CocoaPods without the `use_frameworks!` directive, you should create a bridging header as documented [here](https://developer.apple.com/library/ios/documentation/Swift/Conceptual/BuildingCocoaApps/MixandMatch.html) and add the following line to your bridging header:

``` objective-c
#import "Traintracks.h"
```

If you have `use_frameworks!` set, you should not use a bridging header and instead use the following line in your swift files:

``` swift
import Traintracks
```

In either case, you can call Traintracks methods with `Traintracks.instance().method(...)`

# Advanced #

This SDK automatically grabs useful data from the phone, including app version, phone model, operating system version, and carrier information. If the user has granted your app location permissions, the SDK will also grab the location of the user. Traintracks will never prompt the user for location permissions itself, this must be done by your app. Traintracks only polls for a location once on startup of the app, once on each app open, and once when the permission is first granted. There is no continuous tracking of location. If you wish to disable location tracking done by the app, you can call `[[Traintracks instance] disableLocationListening]` at any point. If you want location tracking disabled on startup of the app, call disableLocationListening before you call `initializeApiKey:`. You can always reenable location tracking through Traintracks with `[[Traintracks instance] enableLocationListening]`.

User IDs are automatically generated and will default to device specific identifiers if not specified.

Device IDs are randomly generated. You can, however, choose to instead use the identifierForVendor (if available) by calling `[[Traintracks instance] useAdvertisingIdForDeviceId]` before initializing with your API key. You can also retrieve the Device ID that Traintracks uses with `[[Traintracks instance] getDeviceId]`.

If you have your own system for tracking device IDs and would like to set a custom device ID, you can do so with `[[Traintracks instance] setDeviceId:@"CUSTOM_DEVICE_ID"];` **Note: this is not recommended unless you really know what you are doing.** Make sure the device ID you set is sufficiently unique (we recommend something like a UUID - see `[TTUtils generateUUID]` for an example on how to generate) to prevent conflicts with other devices in our system.

This code will work with both ARC and non-ARC projects. Preprocessor macros are used to determine which version of the compiler is being used.

The SDK includes support for SSL pinning, but it is undocumented and recommended against unless you have a specific need. Please contact Traintracks support before you ship any products with SSL pinning enabled so that we are aware and can provide documentation and implementation help.
