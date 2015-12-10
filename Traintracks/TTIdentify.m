//
//  TTIdentify.m
//

#import <Foundation/Foundation.h>
#import "TTIdentify.h"
#import "TTARCMacros.h"
#import "TTConstants.h"

@interface TTIdentify()
@end

@implementation TTIdentify
{
    NSMutableSet *_userProperties;
}

- (id)init
{
    if (self = [super init]) {
        _userPropertyOperations = [[NSMutableDictionary alloc] init];
        _userProperties = [[NSMutableSet alloc] init];
    }
    return self;
}

+ (instancetype)identify
{
    return SAFE_ARC_AUTORELEASE([[self alloc] init]);
}

- (void)dealloc
{
    SAFE_ARC_RELEASE(_userPropertyOperations);
    SAFE_ARC_RELEASE(_userProperties);
    SAFE_ARC_SUPER_DEALLOC();
}

- (TTIdentify*)add:(NSString*) property value:(NSObject*) value
{
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]) {
        [self addToUserProperties:TT_OP_ADD property:property value:value];
    } else {
        NSLog(@"Unsupported value type for ADD operation, expecting NSNumber or NSString");
    }
    return self;
}

- (TTIdentify*)set:(NSString*) property value:(NSObject*) value
{
    [self addToUserProperties:TT_OP_SET property:property value:value];
    return self;
}

- (TTIdentify*)setOnce:(NSString*) property value:(NSObject*) value
{
    [self addToUserProperties:TT_OP_SET_ONCE property:property value:value];
    return self;
}

- (TTIdentify*)unset:(NSString*) property
{
    [self addToUserProperties:TT_OP_UNSET property:property value:@"-"];
    return self;
}

- (void)addToUserProperties:(NSString*)operation property:(NSString*) property value:(NSObject*) value
{
    // check if property already used in a previous operation
    if ([_userProperties containsObject:property]) {
        NSLog(@"Already used property '%@' in previous operation, ignoring for operation '%@'", property, operation);
        return;
    }

    NSMutableDictionary *operations = [_userPropertyOperations objectForKey:operation];
    if (operations == nil) {
        operations = [NSMutableDictionary dictionary];
        [_userPropertyOperations setObject:operations forKey:operation];
    }
    [operations setObject:value forKey:property];
    [_userProperties addObject:property];
}

@end
