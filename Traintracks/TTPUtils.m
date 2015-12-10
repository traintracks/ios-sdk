//
//  AMPUtil.m
//  Pods
//
//  Created by Daniel Jih on 10/4/15.
//
//

#import <Foundation/Foundation.h>
#import "TTUtils.h"
#import "TTARCMacros.h"

@interface TTUtils()
@end

@implementation TTUtils

+ (id)alloc
{
    // Util class cannot be instantiated.
    return nil;
}

+ (NSString*)generateUUID
{
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
#if __has_feature(objc_arc)
    NSString *uuidStr = (__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid);
#else
    NSString *uuidStr = (NSString *) CFUUIDCreateString(kCFAllocatorDefault, uuid);
#endif
    CFRelease(uuid);
    return SAFE_ARC_AUTORELEASE(uuidStr);
}

@end