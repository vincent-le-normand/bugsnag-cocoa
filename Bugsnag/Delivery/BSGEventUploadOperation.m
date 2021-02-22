//
//  BSGEventUploadOperation.m
//  Bugsnag
//
//  Created by Nick Dowell on 17/02/2021.
//  Copyright © 2021 Bugsnag Inc. All rights reserved.
//

#import "BSGEventUploadOperation.h"

#import "BSGFileLocations.h"
#import "BSG_RFC3339DateTool.h"
#import "BugsnagAppWithState+Private.h"
#import "BugsnagConfiguration+Private.h"
#import "BugsnagError+Private.h"
#import "BugsnagEvent+Private.h"
#import "BugsnagKeys.h"
#import "BugsnagLogger.h"
#import "BugsnagNotifier.h"


static NSString * const EventPayloadVersion = @"4.0";

typedef NS_ENUM(NSUInteger, BSGEventUploadOperationState) {
    BSGEventUploadOperationStateReady,
    BSGEventUploadOperationStateExecuting,
    BSGEventUploadOperationStateFinished,
};

// MARK: -

@implementation BSGEventUploadOperation {
    BSGEventUploadOperationState _state;
}

- (instancetype)initWithDelegate:(id<BSGEventUploadOperationDelegate>)delegate {
    if (self = [super init]) {
        _delegate = delegate;
    }
    return self;
}

- (void)startUpload:(void (^)(void))completionHandler {
    bsg_log_debug(@"Preparing event %@", self.name);
    
    BugsnagEvent *event = [self loadEvent];
    if (!event) {
        bsg_log_err(@"Failed to load event %@", self.name);
        [self deleteEvent];
        completionHandler();
        return;
    }
    
    BugsnagConfiguration *configuration = self.delegate.configuration;
    
    if (!configuration.shouldSendReports || ![event shouldBeSent]) {
        bsg_log_info(@"Discarding event %@ because releaseStage not in enabledReleaseStages", self.name);
        [self deleteEvent];
        completionHandler();
        return;
    }
    
    NSString *errorClass = event.errors.firstObject.errorClass;
    if ([configuration shouldDiscardErrorClass:errorClass]) {
        bsg_log_info(@"Discarding event %@ because errorClass \"%@\" matches configuration.discardClasses", self.name, errorClass);
        [self deleteEvent];
        completionHandler();
        return;
    }
    
    for (BugsnagOnSendErrorBlock block in configuration.onSendBlocks) {
        @try {
            if (!block(event)) {
                [self deleteEvent];
                completionHandler();
                return;
            }
        } @catch (NSException *exception) {
            bsg_log_err(@"Ignoring exception thrown by onSend callback: %@", exception);
        }
    }
    
    NSDictionary *eventPayload = [event toJsonWithRedactedKeys:configuration.redactedKeys];

    NSString *apiKey = event.apiKey ?: configuration.apiKey;
    
    NSMutableDictionary *requestPayload = [NSMutableDictionary dictionary];
    requestPayload[BSGKeyApiKey] = apiKey;
    requestPayload[BSGKeyEvents] = @[eventPayload];
    requestPayload[BSGKeyNotifier] = [self.delegate.notifier toDict];
    requestPayload[BSGKeyPayloadVersion] = EventPayloadVersion;
    
    NSMutableDictionary *requestHeaders = [NSMutableDictionary dictionary];
    requestHeaders[BugsnagHTTPHeaderNameApiKey] = apiKey;
    requestHeaders[BugsnagHTTPHeaderNamePayloadVersion] = EventPayloadVersion;
    requestHeaders[BugsnagHTTPHeaderNameSentAt] = [BSG_RFC3339DateTool stringFromDate:[NSDate date]];
    requestHeaders[BugsnagHTTPHeaderNameStacktraceTypes] = [event.stacktraceTypes componentsJoinedByString:@","];
    
    [self.delegate.apiClient sendJSONPayload:requestPayload headers:requestHeaders toURL:configuration.notifyURL
                           completionHandler:^(BugsnagApiClientDeliveryStatus status, NSError *error) {
        
        switch (status) {
            case BugsnagApiClientDeliveryStatusDelivered:
                bsg_log_debug(@"Uploaded event %@", self.name);
                [self deleteEvent];
                break;
                
            case BugsnagApiClientDeliveryStatusFailed:
                bsg_log_debug(@"Upload failed; will retry event %@", self.name);
                [self storeEventPayload:eventPayload inDirectory:[BSGFileLocations current].events];
                break;
                
            case BugsnagApiClientDeliveryStatusUndeliverable:
                bsg_log_debug(@"Upload failed; will discard event %@", self.name);
                [self deleteEvent];
                break;
        }
        
        completionHandler();
    }];
}

// MARK: Subclassing

- (BugsnagEvent *)loadEvent {
    return nil;
}

- (void)deleteEvent {
}

- (void)storeEventPayload:(NSDictionary *)eventPayload inDirectory:(NSString *)directory {
}

// MARK: Asynchronous NSOperation implementation

- (void)start {
    if ([self isCancelled]) {
        [self setFinished];
        return;
    }
    
    [self willChangeValueForKey:NSStringFromSelector(@selector(isExecuting))];
    _state = BSGEventUploadOperationStateExecuting;
    [self didChangeValueForKey:NSStringFromSelector(@selector(isExecuting))];
    
    [self startUpload:^{
        [self setFinished];
    }];
}

- (void)setFinished {
    if (_state == BSGEventUploadOperationStateFinished) {
        return;
    }
    [self willChangeValueForKey:NSStringFromSelector(@selector(isExecuting))];
    [self willChangeValueForKey:NSStringFromSelector(@selector(isFinished))];
    _state = BSGEventUploadOperationStateFinished;
    [self didChangeValueForKey:NSStringFromSelector(@selector(isExecuting))];
    [self didChangeValueForKey:NSStringFromSelector(@selector(isFinished))];
}

- (BOOL)isAsynchronous {
    return YES;
}

- (BOOL)isReady {
    return _state == BSGEventUploadOperationStateReady;
}

- (BOOL)isExecuting {
    return _state == BSGEventUploadOperationStateExecuting;
}

- (BOOL)isFinished {
    return _state == BSGEventUploadOperationStateFinished;
}

@end
