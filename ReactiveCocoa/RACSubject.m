//!
//  RACSubject.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/9/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubject.h"
#import "EXTScope.h"
#import "RACCompoundDisposable.h"
#import "RACPassthroughSubscriber.h"

@interface RACSubject ()

// Contains all current subscribers to the receiver.
//
// This should only be used while synchronized on `self`.
@property (nonatomic, strong, readonly) NSMutableArray *subscribers;

// Contains all of the receiver's subscriptions to other signals.
@property (nonatomic, strong, readonly) RACCompoundDisposable *disposable;

// Enumerates over each of the receiver's `subscribers` and invokes `block` for
// each.
- (void)enumerateSubscribersUsingBlock:(void (^)(id<RACSubscriber> subscriber))block;

@end

@implementation RACSubject

#pragma mark Lifecycle

+ (instancetype)subject {
	return [[self alloc] init];
}

- (id)init {
	self = [super init];
	if (self == nil) return nil;

	_disposable = [RACCompoundDisposable compoundDisposable];
	_subscribers = [[NSMutableArray alloc] initWithCapacity:1];
	
	return self;
}

- (void)dealloc {
	[self.disposable dispose];
}

#pragma mark Subscription

/// 可以被多个订阅者订阅
/// 跟RACDynamicSignal不同的是 RACSubject将订阅者保存起来 接到信号则转发 而RACDynamicSignal每次都会重新执行一次didSubscribe
/// 将订阅者放入_subscribers 返回的disposable将其从_subscribers中移除
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);

	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];
    
	NSMutableArray *subscribers = self.subscribers;
	@synchronized (subscribers) {
		[subscribers addObject:subscriber];
	}
	
	return [RACDisposable disposableWithBlock:^{
		@synchronized (subscribers) {
            //[subscriber removeObject:subscriber];实现是从头至尾遍历 这里从尾巴开始遍历再移除性能更佳
			// Since newer subscribers are generally shorter-lived, search
			// starting from the end of the list.
			NSUInteger index = [subscribers indexOfObjectWithOptions:NSEnumerationReverse passingTest:^ BOOL (id<RACSubscriber> obj, NSUInteger index, BOOL *stop) {
				return obj == subscriber;
			}];
			if (index != NSNotFound) [subscribers removeObjectAtIndex:index];
            
		}
	}];
}

- (void)enumerateSubscribersUsingBlock:(void (^)(id<RACSubscriber> subscriber))block {
	NSArray *subscribers;
	@synchronized (self.subscribers) {
		subscribers = [self.subscribers copy];
	}

	for (id<RACSubscriber> subscriber in subscribers) {
		block(subscriber);
	}
}

#pragma mark RACSubscriber

/// 将收到的信号转发给自己的订阅者

- (void)sendNext:(id)value {
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendNext:value];
	}];
}

- (void)sendError:(NSError *)error {
	[self.disposable dispose];
	
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendError:error];
	}];
}

- (void)sendCompleted {
	[self.disposable dispose];
	
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendCompleted];
	}];
}

/// error或者complete后 [self.disposable dispose];
/// 这样只要有一个信号结束 就结束其他所有信号的订阅
- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)d {
	if (d.disposed) return;
	[self.disposable addDisposable:d];

	@weakify(self, d);
	[d addDisposable:[RACDisposable disposableWithBlock:^{
		@strongify(self, d);
		[self.disposable removeDisposable:d];
	}]];
}

@end
