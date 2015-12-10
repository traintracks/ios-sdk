//
//  TTConstants.m

#import "TTConstants.h"

NSString *const kTTLibrary = @"traintracks-ios";
NSString *const kTTPlatform = @"iOS";
NSString *const kTTVersion = @"1.0";
NSString *const kTTEventLogDomain = @"api.traintracks.io";
NSString *const kTTEventLogUrl = @"https://api.traintracks.io/v1/events";
const int kTTApiVersion = 3;
const int kTTDBVersion = 3;
const int kTTDBFirstVersion = 2; // to detect if DB exists yet
const int kTTEventUploadThreshold = 30;
const int kTTEventUploadMaxBatchSize = 100;
const int kTTEventMaxCount = 1000;
const int kTTEventRemoveBatchSize = 20;
const int kTTEventUploadPeriodSeconds = 30; // 30s
const long kTTMinTimeBetweenSessionsMillis = 5 * 60 * 1000; // 5m
const int kTTMaxStringLength = 1024;

NSString *const IDENTIFY_EVENT = @"$identify";
NSString *const TT_OP_ADD = @"$add";
NSString *const TT_OP_SET = @"$set";
NSString *const TT_OP_SET_ONCE = @"$setOnce";
NSString *const TT_OP_UNSET = @"$unset";
