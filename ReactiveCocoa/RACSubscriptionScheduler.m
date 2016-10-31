//!
//  RACSubscriptionScheduler.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubscriptionScheduler.h"
#import "RACScheduler+Private.h"

@interface RACSubscriptionScheduler ()

// A private background scheduler on which to subscribe if the +currentScheduler
// is unknown.
@property (nonatomic, strong, readonly) RACScheduler *backgroundScheduler;

@end

@implementation RACSubscriptionScheduler

#pragma mark Lifecycle

- (id)init {
	self = [super initWithName:@"com.ReactiveCocoa.RACScheduler.subscriptionScheduler"];
	if (self == nil) return nil;
    //RACTargetQueueScheduler
	_backgroundScheduler = [RACScheduler scheduler];

	return self;
}

#pragma mark RACScheduler
/// 主线程 或者当前线程有scheduler 则直接执行 否则在backgroundScheduler中执行
- (RACDisposable *)schedule:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

    // 一种情况
    // 1. diliverOn会返回一个新的信号 这个信号会在这里进行订阅diliverOn的原信号
    // 2. 原信号的didSubscribe又会在这里中执行
    // 1中如果currentScheduler == nil 则会在backgroundScheduler中执行
    // 这时再执行2则currentScheduler non-nil 所以直接执行了
    
    // 这样保证了1 订阅过程不阻塞主线程 2 在1的基础上尽快执行
    
	if (RACScheduler.currentScheduler == nil) return [self.backgroundScheduler schedule:block];

	block();
	return nil;
}

- (RACDisposable *)after:(NSDate *)date schedule:(void (^)(void))block {
	RACScheduler *scheduler = RACScheduler.currentScheduler ?: self.backgroundScheduler;
	return [scheduler after:date schedule:block];
}

- (RACDisposable *)after:(NSDate *)date repeatingEvery:(NSTimeInterval)interval withLeeway:(NSTimeInterval)leeway schedule:(void (^)(void))block {
	RACScheduler *scheduler = RACScheduler.currentScheduler ?: self.backgroundScheduler;
	return [scheduler after:date repeatingEvery:interval withLeeway:leeway schedule:block];
}

@end
