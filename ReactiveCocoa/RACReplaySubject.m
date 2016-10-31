//!
//  RACReplaySubject.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/14/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACReplaySubject.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACScheduler+Private.h"
#import "RACSubscriber.h"
#import "RACTuple.h"

const NSUInteger RACReplaySubjectUnlimitedCapacity = NSUIntegerMax;

@interface RACReplaySubject ()

@property (nonatomic, assign, readonly) NSUInteger capacity;

// These properties should only be modified while synchronized on self.
@property (nonatomic, strong, readonly) NSMutableArray *valuesReceived;

/// 表示收到过complete或者error

@property (nonatomic, assign) BOOL hasCompleted;
@property (nonatomic, assign) BOOL hasError;
@property (nonatomic, strong) NSError *error;

@end


@implementation RACReplaySubject

#pragma mark Lifecycle

+ (instancetype)replaySubjectWithCapacity:(NSUInteger)capacity {
	return [(RACReplaySubject *)[self alloc] initWithCapacity:capacity];
}

- (instancetype)init {
	return [self initWithCapacity:RACReplaySubjectUnlimitedCapacity];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
	self = [super init];
	if (self == nil) return nil;
	
	_capacity = capacity;
	_valuesReceived = (capacity == RACReplaySubjectUnlimitedCapacity ? [NSMutableArray array] : [NSMutableArray arrayWithCapacity:capacity]);
	
	return self;
}

#pragma mark RACSignal

/// 先把收到过的值向subscriber发一遍 然后调用父类方法 以便接收以后的值
/// 在subscriptionScheduler中发送
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

	RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
		@synchronized (self) {
			for (id value in self.valuesReceived) {
				if (compoundDisposable.disposed) return;

				[subscriber sendNext:(value == RACTupleNil.tupleNil ? nil : value)];
			}

			if (compoundDisposable.disposed) return;

			if (self.hasCompleted) {
				[subscriber sendCompleted];
			} else if (self.hasError) {
				[subscriber sendError:self.error];
			} else {
				RACDisposable *subscriptionDisposable = [super subscribe:subscriber];
				[compoundDisposable addDisposable:subscriptionDisposable];
			}
		}
	}];

	[compoundDisposable addDisposable:schedulingDisposable];

	return compoundDisposable;
}

#pragma mark RACSubscriber

/// 先保存值 然后再调用父类方法发送给订阅者
/// 若容量capacity满了 则移除最早的值

- (void)sendNext:(id)value {
	@synchronized (self) {
		[self.valuesReceived addObject:value ?: RACTupleNil.tupleNil];
		[super sendNext:value];
		
		if (self.capacity != RACReplaySubjectUnlimitedCapacity && self.valuesReceived.count > self.capacity) {
			[self.valuesReceived removeObjectsInRange:NSMakeRange(0, self.valuesReceived.count - self.capacity)];
		}
	}
}

- (void)sendCompleted {
	@synchronized (self) {
		self.hasCompleted = YES;
		[super sendCompleted];
	}
}

- (void)sendError:(NSError *)e {
	@synchronized (self) {
		self.hasError = YES;
		self.error = e;
		[super sendError:e];
	}
}

@end
