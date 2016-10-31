//!
//  RACSignalSequence.m
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2012-11-09.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSignalSequence.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"

@interface RACSignalSequence ()

// Replays the signal given on initialization.
@property (nonatomic, strong, readonly) RACReplaySubject *subject;

@end

@implementation RACSignalSequence

#pragma mark Lifecycle

/// 初始化一个RACReplaySubject来回放历史信号值 默认容量RACReplaySubjectUnlimitedCapacity
/// 立即订阅signal
+ (RACSequence *)sequenceWithSignal:(RACSignal *)signal {
	RACSignalSequence *seq = [[self alloc] init];

	RACReplaySubject *subject = [RACReplaySubject subject];
	[signal subscribeNext:^(id value) {
		[subject sendNext:value];
	} error:^(NSError *error) {
		[subject sendError:error];
	} completed:^{
		[subject sendCompleted];
	}];

	seq->_subject = subject;
	return seq;
}

#pragma mark RACSequence

/// subject中的第一个next值
- (id)head {
	id value = [self.subject firstOrDefault:self];

	if (value == self) {
		return nil;
	} else {
		return value ?: NSNull.null;
	}
}

/// 除第一个之外的其他值
- (RACSequence *)tail {
	RACSequence *sequence = [self.class sequenceWithSignal:[self.subject skip:1]];
	sequence.name = self.name;
	return sequence;
}

- (NSArray *)array {
	return self.subject.toArray;
}

#pragma mark NSObject

/// 订阅subject 取得所有值然后马上退订
- (NSString *)description {
	// Synchronously accumulate the values that have been sent so far.
	NSMutableArray *values = [NSMutableArray array];
	RACDisposable *disposable = [self.subject subscribeNext:^(id value) {
		@synchronized (values) {
			[values addObject:value ?: NSNull.null];
		}
	}];

	[disposable dispose];

	return [NSString stringWithFormat:@"<%@: %p>{ name = %@, values = %@ … }", self.class, self, self.name, values];
}

@end
