//!
//  RACCommand.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/3/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACCommand.h"
#import "EXTScope.h"
#import "NSArray+RACSequenceAdditions.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACPropertySubscribing.h"
#import "RACMulticastConnection.h"
#import "RACReplaySubject.h"
#import "RACScheduler.h"
#import "RACSequence.h"
#import "RACSignal+Operations.h"
#import <libkern/OSAtomic.h>

NSString * const RACCommandErrorDomain = @"RACCommandErrorDomain";
NSString * const RACUnderlyingCommandErrorKey = @"RACUnderlyingCommandErrorKey";

const NSInteger RACCommandErrorNotEnabled = 1;

@interface RACCommand () {
	// The mutable array backing `activeExecutionSignals`.
	//
	// This should only be used while synchronized on `self`.
	NSMutableArray *_activeExecutionSignals;

	// Atomic backing variable for `allowsConcurrentExecution`.
    // 默认0 即NO
	volatile uint32_t _allowsConcurrentExecution;
}

// An array of signals representing in-flight executions, in the order they
// began.
//
// This property is KVO-compliant.
@property (atomic, copy, readonly) NSArray *activeExecutionSignals;

// `enabled`, but without a hop to the main thread.
//
// Values from this signal may arrive on any thread.
@property (nonatomic, strong, readonly) RACSignal *immediateEnabled;

// The signal block that the receiver was initialized with.
// 初始化时候提供的signalBlock
@property (nonatomic, copy, readonly) RACSignal * (^signalBlock)(id input);

// Adds a signal to `activeExecutionSignals` and generates a KVO notification.
- (void)addActiveExecutionSignal:(RACSignal *)signal;

// Removes a signal from `activeExecutionSignals` and generates a KVO
// notification.
- (void)removeActiveExecutionSignal:(RACSignal *)signal;

@end

@implementation RACCommand

#pragma mark Properties

- (BOOL)allowsConcurrentExecution {
	return _allowsConcurrentExecution != 0;
}

- (void)setAllowsConcurrentExecution:(BOOL)allowed {
	[self willChangeValueForKey:@keypath(self.allowsConcurrentExecution)];

	if (allowed) {
		OSAtomicOr32Barrier(1, &_allowsConcurrentExecution);
	} else {
		OSAtomicAnd32Barrier(0, &_allowsConcurrentExecution);
	}

	[self didChangeValueForKey:@keypath(self.allowsConcurrentExecution)];
}

- (NSArray *)activeExecutionSignals {
	@synchronized (self) {
		return [_activeExecutionSignals copy];
	}
}

- (void)addActiveExecutionSignal:(RACSignal *)signal {
	NSCParameterAssert([signal isKindOfClass:RACSignal.class]);

	@synchronized (self) {
		// The KVO notification has to be generated while synchronized, because
		// it depends on the index remaining consistent.
		NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:_activeExecutionSignals.count];
		[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
		[_activeExecutionSignals addObject:signal];
		[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
	}
}

- (void)removeActiveExecutionSignal:(RACSignal *)signal {
	NSCParameterAssert([signal isKindOfClass:RACSignal.class]);

	@synchronized (self) {
		// The indexes have to be calculated and the notification generated
		// while synchronized, because they depend on the indexes remaining
		// consistent.
		NSIndexSet *indexes = [_activeExecutionSignals indexesOfObjectsPassingTest:^ BOOL (RACSignal *obj, NSUInteger index, BOOL *stop) {
			return obj == signal;
		}];

		if (indexes.count == 0) return;

		[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
		[_activeExecutionSignals removeObjectsAtIndexes:indexes];
		[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@keypath(self.activeExecutionSignals)];
	}
}

#pragma mark Lifecycle

- (id)init {
	NSCAssert(NO, @"Use -initWithSignalBlock: instead");
	return nil;
}

- (id)initWithSignalBlock:(RACSignal * (^)(id input))signalBlock {
	return [self initWithEnabled:nil signalBlock:signalBlock];
}

/// signalBlock在每次execute都会执行创建一个信号
/// enabledSignal 用来指示命令是否可以执行 为nil的话 默认为return:@(YES)
- (id)initWithEnabled:(RACSignal *)enabledSignal signalBlock:(RACSignal * (^)(id input))signalBlock {
	NSCParameterAssert(signalBlock != nil);

	self = [super init];
	if (self == nil) return nil;

	_activeExecutionSignals = [[NSMutableArray alloc] init];
	_signalBlock = [signalBlock copy];

	// A signal of additions to `activeExecutionSignals`.
    // KVO activeExecutionSignals activeExecutionSignals是手动KVO的
	RACSignal *newActiveExecutionSignals = [[[[[self
		rac_valuesAndChangesForKeyPath:@keypath(self.activeExecutionSignals) options:NSKeyValueObservingOptionNew observer:nil]
		reduceEach:^(id _, NSDictionary *change) {
			NSArray *signals = change[NSKeyValueChangeNewKey];
			if (signals == nil) return [RACSignal empty];

			return [signals.rac_sequence signalWithScheduler:RACScheduler.immediateScheduler];
		}]
		concat]
		publish]
		autoconnect];

    // 订阅_executionSignals 返回的是当前正在执行的信号数组
    // 为了收到最新创建的信号 要先订阅这个信号 再执行excute
	_executionSignals = [[[newActiveExecutionSignals
		map:^(RACSignal *signal) {
			return [signal catchTo:[RACSignal empty]];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		setNameWithFormat:@"%@ -executionSignals", self];
	
	// `errors` needs to be multicasted so that it picks up all
	// `activeExecutionSignals` that are added.
	//
	// In other words, if someone subscribes to `errors` _after_ an execution
	// has started, it should still receive any error from that execution.
    // 订阅所有正在执行的信号
    // 执行的信号中出现错误 会被以sendNext的形式发出 ignoreValues只接收error
    // excute返回的是RACReplaySubject 放入newActiveExecutionSignals的也是RACReplaySubject 这就避免了这里重复订阅造成副作用重复执行
	RACMulticastConnection *errorsConnection = [[[newActiveExecutionSignals
		flattenMap:^(RACSignal *signal) {
			return [[signal
				ignoreValues]
				catch:^(NSError *error) {
					return [RACSignal return:error];
				}];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		publish];
	
    // excute创建的信号发生的错误通过这个属性发出 这里接收到的任何next值都是错误
	_errors = [errorsConnection.signal setNameWithFormat:@"%@ -errors", self];
	[errorsConnection connect];

    // 活动信号数量大于0
	RACSignal *immediateExecuting = [RACObserve(self, activeExecutionSignals) map:^(NSArray *activeSignals) {
		return @(activeSignals.count > 0);
	}];

    // 命令是否正在执行 保存immediateExecuting最后发出的值
    // replayLast中已经connect
	_executing = [[[[[immediateExecuting
		deliverOn:RACScheduler.mainThreadScheduler]
		// This is useful before the first value arrives on the main thread.
		startWith:@NO]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -executing", self];

    // 如果允许串行则YES 否则当前有活动信号则NO 否则YES
    // RACObserve会立即发出当前值
	RACSignal *moreExecutionsAllowed = [RACSignal
		if:RACObserve(self, allowsConcurrentExecution)
		then:[RACSignal return:@YES]
		else:[immediateExecuting not]];
	
    
	if (enabledSignal == nil) {
		enabledSignal = [RACSignal return:@YES];
	} else {
        // startWith:@YES 未收到enabledSignal之前默认为NO
        // replayLast保存最新的值
        // 至少有个默认值YES
		enabledSignal = [[[enabledSignal
			startWith:@YES]
			takeUntil:self.rac_willDeallocSignal]
			replayLast];
	}
	
    // enabledSignal & moreExecutionsAllowed 与
	_immediateEnabled = [[RACSignal
		combineLatest:@[ enabledSignal, moreExecutionsAllowed ]]
		and];
	
    // 跟_immediateEnabled差别在deliverOn _enabled暴露在.h中
	_enabled = [[[[[self.immediateEnabled
		take:1]
		concat:[[self.immediateEnabled skip:1] deliverOn:RACScheduler.mainThreadScheduler]]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -enabled", self];

	return self;
}

#pragma mark Execution
/// 执行命令 相当于创建一个信号并返回
/// 如果不可用 返回[RACSignal error:error];
/// 如果可用 调用signalBlock创建一个信号
///    1.subscribeOn:RACScheduler.mainThreadScheduler
///    2.multicast
///    3.connect
///    4.addActiveExecutionSignal
/// 实际返回的是一个RACReplaySubject 保证创建的信号被订阅且只会被订阅一次
- (RACSignal *)execute:(id)input {
	// `immediateEnabled` is guaranteed to send a value upon subscription, so
	// -first is acceptable here.
    // 这里线程不会被阻塞 因为immediateEnabled至少有一个值 无需等待
	BOOL enabled = [[self.immediateEnabled first] boolValue];
	if (!enabled) {
		NSError *error = [NSError errorWithDomain:RACCommandErrorDomain code:RACCommandErrorNotEnabled userInfo:@{
			NSLocalizedDescriptionKey: NSLocalizedString(@"The command is disabled and cannot be executed", nil),
			RACUnderlyingCommandErrorKey: self
		}];

		return [RACSignal error:error];
	}

	RACSignal *signal = self.signalBlock(input);
	NSCAssert(signal != nil, @"nil signal returned from signal block for value: %@", input);

	// We subscribe to the signal on the main thread so that it occurs _after_
	// -addActiveExecutionSignal: completes below.
	//
	// This means that `executing` and `enabled` will send updated values before
	// the signal actually starts performing work.
	RACMulticastConnection *connection = [[signal
		subscribeOn:RACScheduler.mainThreadScheduler]
		multicast:[RACReplaySubject subject]];
	
	@weakify(self);

    // activeExecutionSignalskVO触发 executing发出新值
    // 如果不支持ConcurrentExecution immediateEnabled 也随之改变
	[self addActiveExecutionSignal:connection.signal];
	[connection.signal subscribeError:^(NSError *error) {
		@strongify(self);
		[self removeActiveExecutionSignal:connection.signal];
	} completed:^{
		@strongify(self);
		[self removeActiveExecutionSignal:connection.signal];
	}];

	[connection connect];
	return [connection.signal setNameWithFormat:@"%@ -execute: %@", self, [input rac_description]];
}

#pragma mark NSKeyValueObserving

/// 手动KVO
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
	// Generate all KVO notifications manually to avoid the performance impact
	// of unnecessary swizzling.
	return NO;
}

@end
