//
//  AMPIdentify.h
//

@interface TTIdentify : NSObject

@property (nonatomic, strong, readonly) NSMutableDictionary *userPropertyOperations;

+ (instancetype)identify;
- (TTIdentify*)add:(NSString*) property value:(NSObject*) value;
- (TTIdentify*)set:(NSString*) property value:(NSObject*) value;
- (TTIdentify*)setOnce:(NSString*) property value:(NSObject*) value;
- (TTIdentify*)unset:(NSString*) property;

@end
