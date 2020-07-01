//
//  ExtPromise.h
//  ExtPromise
//
//  Created by hang.pan on 2020/03/02.

#import <Foundation/Foundation.h>

@class ExtPromise;

typedef NS_ENUM(NSInteger, ExtPromiseState) {
    ExtPromiseStatePending = 0,
    ExtPromiseStateFulfilled,
    ExtPromiseStateRejected
};

typedef id(^ExtPromiseFulfillment)(id value);
typedef id(^ExtPromiseRejection)(NSError * error);
typedef id(^ExtPromiseFinal)(id value);

typedef void(^ExtPromiseFulfill)(id value);
typedef void(^ExtPromiseReject)(NSError * error);
typedef void(^ExtPromiseExecutorBlock)(ExtPromiseFulfill fulfillWithValue, ExtPromiseReject rejectWithError);

typedef ExtPromise *(^ExtPromiseBothReturnBlock)(ExtPromiseFulfillment, ExtPromiseRejection);
typedef ExtPromise *(^ExtPromiseThenReturnBlock)(ExtPromiseFulfillment);
typedef ExtPromise *(^ExtPromiseCatchReturnBlock)(ExtPromiseRejection);
typedef ExtPromise *(^ExtPromiseFinallyReturnBlock)(ExtPromiseFinal);
typedef ExtPromise *(^ExtPromiseAllReturnBlock)(NSArray<ExtPromise *> * array);
typedef ExtPromise *(^ExtPromiseRaceReturnBlock)(NSArray<ExtPromise *> * array);

extern NSString * const kExtPromiseInitException;
extern NSString * const kExtPromiseErrorDomain;
extern NSString * const kExtPromiseErrorUserInfoValueKey;
extern NSInteger const kExtPromiseCatchExceptionErrorCode;
extern NSInteger const kExtPromiseRejectErrorCode;

@interface ExtPromise : NSObject

@property (nonatomic, assign, class)BOOL enableLogging;

@property (nonatomic, strong, readonly)id value;

@property (nonatomic, assign, readonly)ExtPromiseState state;

- (instancetype)initWithExecutor:(ExtPromiseExecutorBlock)executor;

- (void(^)(id value))fulfill;

- (void(^)(NSError * error))reject;

+ (ExtPromise *(^)(id value))fulfill;

+ (ExtPromise *(^)(NSError * error))reject;

- (ExtPromiseBothReturnBlock)both;

- (ExtPromiseThenReturnBlock)then;

- (ExtPromiseCatchReturnBlock)catch;

- (ExtPromiseFinallyReturnBlock)finally;

+ (ExtPromiseAllReturnBlock)all;

+ (ExtPromiseRaceReturnBlock)race;

+ (ExtPromise *)findHeadPromise:(ExtPromise *)promise;

+ (ExtPromise *)findTailPromise:(ExtPromise *)promise;

+ (ExtPromise *)findOriginPromise:(ExtPromise *)promise;

@end

