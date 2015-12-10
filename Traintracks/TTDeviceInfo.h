//
//  TTDeviceInfo.h

@interface TTDeviceInfo : NSObject

-(id) init;
@property (readonly) NSString *appVersion;
@property (readonly) NSString *osName;
@property (readonly) NSString *osVersion;
@property (readonly) NSString *manufacturer;
@property (readonly) NSString *model;
@property (readonly) NSString *carrier;
@property (readonly) NSString *country;
@property (readonly) NSString *language;
@property (readonly) NSString *advertiserId;
@property (readonly) NSString *vendorId;

-(NSString*) generateUUID;

@end