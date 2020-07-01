//
//  ViewController.m
//  Example
//
//  Created by hang_pan on 2020/5/8.
//  Copyright © 2020 hang_pan. All rights reserved.
//

#import "ViewController.h"
#import <ExtPromise/ExtPromise.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    ExtPromise.enableLogging = NO;
    
    ExtPromise *p = [ExtPromise new];
    p.then(^id(id value) {
        p.then(^id(id value) {
            NSLog(@"value-1:%@", value);
            return @1;
        });
        NSLog(@"value-2:%@", value);
        return @2;
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        p.fulfill(@(3));
    });
    
    // a simple demo
    [self mockRequstAWithAccount:@"13271567509" password:@"abc123"].then(^id(NSDictionary *dic){
        NSString *uid = dic[@"uid"];
        NSString *token = dic[@"token"];
        NSLog(@"receive uid : %@, token : %@", uid, token);
        return [self mockRequstBWithUid:uid token:token];
    }).then(^id(NSString *orderId){
        NSLog(@"receive orderId : %@", orderId);
        return [self mockRuestCWithOrderId:orderId];
    }).then(^id(NSDictionary *orderInfo){
        NSLog(@"show orderinfo at screen : %@", orderInfo);
        return nil;
    }).finally(^id(id value) {
        NSLog(@"ExtPromise demo finished!");
        return nil;
    });
}

- (ExtPromise *)mockRequstAWithAccount:(NSString *)account password:(NSString *)password {
    NSLog(@"request A start!");
    ExtPromise *promise = [ExtPromise new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"request A finished!");
            promise.fulfill(@{@"uid":@"10001", @"token":@"FFFF"});
        });
    });
    return promise;
}

- (ExtPromise *)mockRequstBWithUid:(NSString *)uid token:(NSString *)token {
    NSLog(@"request B start!");
    ExtPromise *promise = [ExtPromise new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"request B finished!");
            promise.fulfill(@"20200xxxxxxxxxx");
        });
    });
    return promise;
}

- (ExtPromise *)mockRuestCWithOrderId:(NSString *)orderId {
    NSLog(@"request C start!");
    ExtPromise *promise = [[ExtPromise alloc] initWithExecutor:^(ExtPromiseFulfill fulfillWithValue, ExtPromiseReject rejectWithError) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"request C finished!");
                fulfillWithValue(@{@"orderId":orderId, @"orderDate":@"2020-xx-xx", @"orderOther":@"xxx"});
            });
        });
    }];
    return promise;
}

@end
