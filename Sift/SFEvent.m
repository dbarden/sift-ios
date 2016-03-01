// Copyright (c) 2016 Sift Science. All rights reserved.

@import Foundation;

#import "SFDebug.h"
#import "SFUtils.h"

#import "SFEvent.h"
#import "SFEvent+Private.h"

@implementation SFEvent

+ (SFEvent *)eventWithType:(NSString *)type path:(NSString *)path fields:(NSDictionary *)fields {
    SFEvent *event = [SFEvent new];
    if (type) {
        event.type = type;
    }
    if (path) {
        event.path = path;
    }
    if (fields) {
        event.fields = fields;
    }
    return event;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _time = SFCurrentTime();
        _type = nil;
        _path = nil;
        _userId = nil;
        _fields = nil;
        _deviceProperties = nil;
        _metrics = nil;
    }
    return self;
}

- (BOOL)isEssentiallyEqualTo:(SFEvent *)event {
    return event &&
           ((!_type && !event.type) || [_type isEqualToString:event.type]) &&
           ((!_path && !event.path) || [_path isEqualToString:event.path]) &&
           ((!_userId && !event.userId) || [_userId isEqualToString:event.userId]) &&
           ((!_fields && !event.fields) || [_fields isEqualToDictionary:event.fields]) &&
           ((!_deviceProperties && !event.deviceProperties) || [_deviceProperties isEqualToDictionary:event.deviceProperties]) &&
           ((!_metrics && !event.metrics) || [_metrics isEqualToDictionary:event.metrics]);
}

- (BOOL)sanityCheck {
    // 1. userId is not optional (but all others are optional).
    // 2. Dictionaries must be string-keyed and string-valued.
    return _userId.length &&
           (!_fields || SFIsDictKeyAndValueStringTyped(_fields)) &&
           (!_deviceProperties || SFIsDictKeyAndValueStringTyped(_deviceProperties)) &&
           (!_metrics || SFIsDictKeyAndValueStringTyped(_metrics));
}

#pragma mark - NSCoding

// Keys for NSCoder.
static NSString * const SF_TIME = @"time";
static NSString * const SF_TYPE = @"type";
static NSString * const SF_PATH = @"path";
static NSString * const SF_USER_ID = @"userId";
static NSString * const SF_FIELDS = @"fields";
static NSString * const SF_DEVICE_PROPERTIES = @"deviceProperties";
static NSString * const SF_METRICS = @"metrics";

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (self) {
        _time = [decoder decodeInt64ForKey:SF_TIME];  // NSCoder doesn't support uint64_t :(
        _type = [decoder decodeObjectForKey:SF_TYPE];
        _path = [decoder decodeObjectForKey:SF_PATH];
        _userId = [decoder decodeObjectForKey:SF_USER_ID];
        _fields = [decoder decodeObjectForKey:SF_FIELDS];
        _deviceProperties = [decoder decodeObjectForKey:SF_DEVICE_PROPERTIES];
        _metrics = [decoder decodeObjectForKey:SF_METRICS];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeInt64:_time forKey:SF_TIME];  // NSCoder doesn't support uint64_t :(
    [encoder encodeObject:_type forKey:SF_TYPE];
    [encoder encodeObject:_path forKey:SF_PATH];
    [encoder encodeObject:_userId forKey:SF_USER_ID];
    [encoder encodeObject:_fields forKey:SF_FIELDS];
    [encoder encodeObject:_deviceProperties forKey:SF_DEVICE_PROPERTIES];
    [encoder encodeObject:_metrics forKey:SF_METRICS];
}

#pragma mark - List request object

+ (NSData *)listRequest:(NSArray *)events {
    NSMutableArray *data = [NSMutableArray new];
    for (SFEvent *event in events) {
        NSMutableDictionary *eventRequest = [NSMutableDictionary new];

        [eventRequest setObject:[NSNumber numberWithUnsignedLongLong:event.time] forKey:@"time"];

        if (!event.userId) {
            SF_DEBUG(@"Lack user ID for event: %@", event);
            continue;
        }
        [eventRequest setObject:event.userId forKey:@"user_id"];

        if (!SFAddToRequest(eventRequest, @"mobile_event_type", event.type) ||
            !SFAddToRequest(eventRequest, @"path", event.path) ||
            !SFAddToRequest(eventRequest, @"fields", event.fields) ||
            !SFAddToRequest(eventRequest, @"device_properties", event.deviceProperties) ||
            !SFAddToRequest(eventRequest, @"metrics", event.metrics)) {
            SF_DEBUG(@"Some fields of event are incorrect: %@", event);
            continue;
        }

        [data addObject:eventRequest];
    }
    NSDictionary *listRequest = @{@"data": data};

    NSError *error;
    NSData *json = [NSJSONSerialization dataWithJSONObject:listRequest options:0 error:&error];
    if (!json) {
        SF_DEBUG(@"Could not create list request JSON object due to %@", [error localizedDescription]);
    }
    return json;
}

static BOOL SFAddToRequest(NSMutableDictionary *request, NSString *field, id value) {
    if (!value) {
        return YES;  // Optional fields are fine.
    } else if ([value isKindOfClass:NSString.class]) {
        NSString *string = (NSString *)value;
        if (string.length) {
            [request setObject:string forKey:field];
        }
        return YES;
    } else if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)value;
        if (SFIsDictKeyAndValueStringTyped(dict)) {
            [request setObject:dict forKey:field];
            return YES;
        } else {
            SF_DEBUG(@"Some of keys and/or values for \"%@\" are not string typed: %@", field, dict);
            return NO;
        }
    } else {
        SF_DEBUG(@"Unsupported type of value for \"%@\": %@", field, value);
        return NO;
    }
}

static BOOL SFIsDictKeyAndValueStringTyped(NSDictionary *dict) {
    for (id key in dict) {
        if (![key isKindOfClass:NSString.class]) {
            return NO;
        }
        id value = [dict objectForKey:key];
        if (![value isKindOfClass:NSString.class]) {
            return NO;
        }
    }
    return YES;
}

@end