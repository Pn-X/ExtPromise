//
//  ExtPromise.m
//  ExtPromise
//
//  Created by hang.pan on 2020/03/02.

#import "ExtPromise.h"

#define lock()  autoreleasepool{}[self.recursiveLock lock]
#define unlock() autoreleasepool{}[self.recursiveLock unlock]

#define retain(p) autoreleasepool{}dispatch_async(ExtPromiseReferenceCounterQueue, ^{[ExtPromiseReferenceCounter addObject:p];})
#define release(p) autoreleasepool{}dispatch_async(ExtPromiseReferenceCounterQueue, ^{[ExtPromiseReferenceCounter removeObject:p];})

NSString * const kExtPromiseInitException = @"ExtPromiseInitException";
NSString * const kExtPromiseErrorDomain = @"ExtPromiseErrorDomain";
NSString * const kExtPromiseErrorUserInfoValueKey = @"Value";
NSInteger const kExtPromiseCatchExceptionErrorCode = -1000;
NSInteger const kExtPromiseRejectErrorCode = -1001;
static NSInteger const kExtPromiseRaceWaitingCount = 1;
void ExtPromiseResolve(ExtPromise * promise,id value);
static NSMutableArray *ExtPromiseReferenceCounter;
static dispatch_queue_t ExtPromiseReferenceCounterQueue;

static BOOL ExtPromiseEnableLogging = YES;

@interface ExtPromise()

@property (nonatomic, strong) NSRecursiveLock *recursiveLock;

@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, assign) NSInteger waitingCount;

@property (nonatomic, strong) id privateValue;
@property (nonatomic, assign) ExtPromiseState privateState;

@property (nonatomic, weak) ExtPromise *parentPromise;
@property (nonatomic, strong) ExtPromise *childPromise;
@property (nonatomic, strong) ExtPromise *previousPromise;
@property (nonatomic, weak) ExtPromise *nextPromise;

@property (nonatomic, strong) NSMutableArray *fulfillmentHandleArray;
@property (nonatomic, strong) NSMutableArray *rejectionHandleArray;

@property (nonatomic, copy) ExtPromiseExecutorBlock executor;
@property (nonatomic, copy) ExtPromiseFulfill fulfillWithValue;
@property (nonatomic, copy) ExtPromiseReject rejectWithError;

@property (nonatomic, copy) NSArray *relatePromiseArray;

@end

@implementation ExtPromise

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ExtPromiseReferenceCounter = [NSMutableArray new];
        ExtPromiseReferenceCounterQueue = dispatch_queue_create("com.beibei.ExtPromise.queue", DISPATCH_QUEUE_SERIAL);
    });
}

+ (BOOL)enableLogging {
    return ExtPromiseEnableLogging;
}

+ (void)setEnableLogging:(BOOL)enableLogging {
    ExtPromiseEnableLogging = enableLogging;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recursiveLock = [[NSRecursiveLock alloc] init];
        @retain(self);
    }
    return self;
}

- (instancetype)initWithExecutor:(ExtPromiseExecutorBlock)executor {
    self = [super init];
    if (self) {
        _recursiveLock = [[NSRecursiveLock alloc] init];
        @retain(self);
        self.privateState = ExtPromiseStatePending;
        self.executor = executor;
        __weak typeof(self) weakSelf = self;
        self.fulfillWithValue = ^(id value) {
            weakSelf.fulfill(value);
        };
        self.rejectWithError = ^(NSError *error) {
            weakSelf.reject(error);
        };
        if (self.executor) {
            @try {
                self.executor(self.fulfillWithValue, self.rejectWithError);
            } @catch (NSException *exception) {
                self.reject([NSError errorWithDomain:kExtPromiseErrorDomain code:kExtPromiseCatchExceptionErrorCode userInfo:@{kExtPromiseErrorUserInfoValueKey:exception}]);
            }
        }
    }
    return self;
}



- (void)dealloc {
#ifdef DEBUG
    if (ExtPromise.enableLogging) {
        NSLog(@"%@ - dealloced", self);
    }
#endif
}

#pragma mark - public method
- (ExtPromiseBothReturnBlock)both {
    return ^(ExtPromiseFulfillment fulfillment, ExtPromiseRejection rejection){
        return [self createPromiseWithFulfillment:fulfillment rejection:rejection];
    };
}

- (ExtPromiseThenReturnBlock)then {
    return ^(ExtPromiseFulfillment fulfillment){
        return [self createPromiseWithFulfillment:fulfillment rejection:nil];
    };
}

- (ExtPromiseCatchReturnBlock)catch {
    return ^(ExtPromiseRejection rejection){
        return [self createPromiseWithFulfillment:nil rejection:rejection];
    };
}

- (ExtPromiseFinallyReturnBlock)finally {
    return ^(ExtPromiseFinal final){
        return [self createPromiseWithFulfillment:final rejection:final];
    };
}

+ (ExtPromiseAllReturnBlock)all {
    return ^(NSArray<ExtPromise *> * array){
        assert(array != nil && array.count > 0);
        ExtPromise * promise = [ExtPromise new];
        promise.semaphore = dispatch_semaphore_create(1);
        promise.waitingCount = array.count;
        promise.relatePromiseArray = array;
        __weak typeof(promise) weakPromise = promise;
        dispatch_block_t finalAction = ^{
            dispatch_semaphore_wait(weakPromise.semaphore, DISPATCH_TIME_FOREVER);
            weakPromise.waitingCount--;
            if (weakPromise.waitingCount == 0) {
                NSMutableArray * resultArray  = [NSMutableArray array];
                id error = nil;
                for (ExtPromise * t in weakPromise.relatePromiseArray) {
                    if (t.privateState == ExtPromiseStateFulfilled) {
                        [resultArray addObject:t.privateValue];
                    } else if (t.privateState == ExtPromiseStateRejected && error == nil){
                        error = t.privateValue;
                    }
                }
                if (error != nil) {
                    weakPromise.reject(error);
                } else {
                    weakPromise.fulfill([NSArray arrayWithArray:resultArray]);
                }
            }
            dispatch_semaphore_signal(weakPromise.semaphore);
        };
        for (ExtPromise * p in array) {
            if (p.privateState == ExtPromiseStatePending) {
                p.finally(^id(id value){
                    finalAction();
                    return nil;
                });
            } else {
                finalAction();
            }
        }
        return promise;
    };
}

+ (ExtPromiseRaceReturnBlock)race {
    return ^(NSArray<ExtPromise *> * array){
        assert(array != nil && array.count > 0);
        ExtPromise * promise = [ExtPromise new];
        promise.semaphore = dispatch_semaphore_create(1);
        promise.waitingCount = kExtPromiseRaceWaitingCount;
        promise.relatePromiseArray = array;
        __weak typeof(promise) weakPromise = promise;
        dispatch_block_t finalAction = ^{
            dispatch_semaphore_wait(weakPromise.semaphore, DISPATCH_TIME_FOREVER);
            weakPromise.waitingCount--;
            if (weakPromise.waitingCount == 0) {
                NSMutableArray * resultArray  = [NSMutableArray array];
                id error = nil;
                for (ExtPromise * t in weakPromise.relatePromiseArray) {
                    if (t.privateState == ExtPromiseStateFulfilled) {
                        [resultArray addObject:t.privateValue];
                    } else if (t.privateState == ExtPromiseStateRejected && error == nil){
                        error = t.privateValue;
                    }
                }
                if (error != nil) {
                    weakPromise.reject(error);
                } else {
                    weakPromise.fulfill([NSArray arrayWithArray:resultArray]);
                }
            }
            dispatch_semaphore_signal(weakPromise.semaphore);
        };
        for (ExtPromise * p in array) {
            if (p.privateState == ExtPromiseStatePending) {
                p.finally(^id(id value){
                    finalAction();
                    return nil;
                });
            } else {
                finalAction();
            }
        }
        return promise;
    };
}


- (void(^)(id value))fulfill {
    __weak typeof(self) weakSelf = self;
    return ^(id value){
        @lock();
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf.privateState != ExtPromiseStatePending) {
            @unlock();
            return;
        }
        strongSelf.privateValue = value;
        strongSelf.privateState = ExtPromiseStateFulfilled;
        for (ExtPromiseFulfillment block in strongSelf.fulfillmentHandleArray) {
            block(strongSelf.privateValue);
        }
        [strongSelf.fulfillmentHandleArray removeAllObjects];
        @release(self);
        @unlock();
    };
}

- (void(^)(NSError * error))reject {
    __weak typeof(self) weakSelf = self;
    return ^(NSError * error){
        @lock();
        if (error == nil || ![error isKindOfClass:[NSError class]]) {
            error = [[NSError alloc] initWithDomain:kExtPromiseErrorDomain code:kExtPromiseRejectErrorCode userInfo:@{kExtPromiseErrorUserInfoValueKey: error == nil ? @"nil":error}];
        }
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf.privateState != ExtPromiseStatePending) {
            @unlock();
            return;
        }
        strongSelf.privateValue = error;
        strongSelf.privateState = ExtPromiseStateRejected;
        for (ExtPromiseRejection block in strongSelf.rejectionHandleArray) {
            block(strongSelf.privateValue);
        }
        [strongSelf.rejectionHandleArray removeAllObjects];
        @release(self);
        @unlock();
    };
}

+ (ExtPromise *(^)(id value))fulfill {
    return ^(id value) {
        ExtPromise * promise = [ExtPromise new];
        promise.fulfill(value);
        return promise;
    };
}

+ (ExtPromise *(^)(NSError * error))reject {
    return ^(id value) {
        ExtPromise * promise = [ExtPromise new];
        promise.reject(value);
        return promise;
    };
}

+ (ExtPromise *)findHeadPromise:(ExtPromise *)promise {
    assert(promise != nil);
    if (promise == nil) {
        return promise;
    }
    ExtPromise * t = promise;
    while (t.previousPromise) {
        t = t.previousPromise;
    }
    return t;
}

+ (ExtPromise *)findTailPromise:(ExtPromise *)promise {
    assert(promise != nil);
    if (promise == nil) {
        return promise;
    }
    ExtPromise * t = promise;
    while (t.nextPromise) {
        t = t.nextPromise;
    }
    return t;
}

+ (ExtPromise *)findOriginPromise:(ExtPromise *)promise {
    assert(promise != nil);
    if (promise == nil) {
        return promise;
    }
    ExtPromise * t = promise;
    while (t.parentPromise) {
        t = t.parentPromise;
        t = [ExtPromise findTailPromise:t];
    }
    return t;
}

#pragma mark - private method

- (ExtPromise *)createPromiseWithFulfillment:(ExtPromiseFulfillment)fulfillment rejection:(ExtPromiseRejection)rejection {
    ExtPromise * newPromise = [[ExtPromise alloc] init];
    newPromise.previousPromise = self;
    self.nextPromise = newPromise;
    __weak typeof(self) weakSelf = self;
    __weak typeof(newPromise) weakNewPromise = newPromise;
    dispatch_block_t fulfillBlock = ^{
        id returnValue = nil;
        @try {
            if (fulfillment) {
                returnValue = fulfillment(weakSelf.privateValue);
            } else {
                returnValue = weakSelf.privateValue;
            }
        } @catch (NSException *exception) {
            returnValue = [NSError errorWithDomain:kExtPromiseErrorDomain code:kExtPromiseCatchExceptionErrorCode userInfo:@{kExtPromiseErrorUserInfoValueKey:exception}];
        } @finally {
            ExtPromiseResolve(weakNewPromise, returnValue);
        }
    };
    dispatch_block_t rejectBlock = ^{
        id returnValue = nil;
        @try {
            if (rejection) {
                returnValue = rejection(weakSelf.privateValue);
            } else {
                returnValue = weakSelf.privateValue;
            }
        } @catch (NSException *exception) {
            returnValue = [NSError errorWithDomain:kExtPromiseErrorDomain code:kExtPromiseCatchExceptionErrorCode userInfo:@{kExtPromiseErrorUserInfoValueKey:exception}];
        } @finally {
            ExtPromiseResolve(weakNewPromise, returnValue);
        }
    };
    @lock();
    if (self.privateState == ExtPromiseStateFulfilled) {
        if (fulfillment) {
            fulfillBlock();
        } else {
            newPromise.fulfill(self.privateValue);
        }
    } else if (self.privateState == ExtPromiseStateRejected) {
        if (rejection) {
            rejectBlock();
        } else {
            newPromise.reject(self.privateValue);
        }
    } else {
        [self.fulfillmentHandleArray addObject:fulfillBlock];
        [self.rejectionHandleArray addObject:rejectBlock];
    }
    @unlock();
    return newPromise;
}

#pragma mark - setter & getter
- (NSMutableArray *)fulfillmentHandleArray {
    if (!_fulfillmentHandleArray) {
        _fulfillmentHandleArray = [NSMutableArray array];
    }
    return _fulfillmentHandleArray;
}

- (NSMutableArray *)rejectionHandleArray {
    if (!_rejectionHandleArray) {
        _rejectionHandleArray = [NSMutableArray array];
    }
    return _rejectionHandleArray;
}

- (id)value {
    return self.privateValue;
}

- (ExtPromiseState)state {
    return self.privateState;
}

@end

void ExtPromiseResolve(ExtPromise * promise,id value) {
    if (promise == nil) {
        return;
    }
    if (value == nil) {
        promise.fulfill(nil);
        return;
    }
    if ([value isKindOfClass:[NSError class]]) {
        promise.reject(value);
        return;
    }
    if ([value isKindOfClass:[ExtPromise class]]) {
        ExtPromise * t = (ExtPromise *)value;
        promise.childPromise = t;
        t.parentPromise = promise;
        __weak typeof(promise) weakPromise = promise;
        if (t.privateState == ExtPromiseStatePending) {
            t.both(^id(id value){
                __strong typeof(weakPromise) strongPromise = weakPromise;
                if (strongPromise) {
                    strongPromise.fulfill(value);
                }
                return nil;
            }, ^id(id value){
                __strong typeof(weakPromise) strongPromise = weakPromise;
                if (strongPromise) {
                    strongPromise.reject(value);
                }
                return nil;
            });
        } else if (t.privateState == ExtPromiseStateFulfilled){
            promise.fulfill(t.privateValue);
        } else {
            promise.reject(t.privateValue);
        }
        return;
    }
    promise.fulfill(value);
}
