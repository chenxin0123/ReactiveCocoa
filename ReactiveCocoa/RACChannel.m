//!
//  RACChannel.m
//  ReactiveCocoa
//
//  Created by Uri Baghin on 01/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACChannel.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"

@interface RACChannelTerminal ()

// The values for this terminal.
@property (nonatomic, strong, readonly) RACSignal *values;

// A subscriber will will send values to the other terminal.
@property (nonatomic, strong, readonly) id<RACSubscriber> otherTerminal;

- (id)initWithValues:(RACSignal *)values otherTerminal:(id<RACSubscriber>)otherTerminal;

@end

// B端会将收到的值通过管道传到A端 反之亦然 所以称为管道
/// 管道两端各一个RACChannelTerminal
/// 但是两个RACChannelTerminal总共就一个信号以及一个订阅者 且这两者都是RACReplaySubject
@implementation RACChannel

- (id)init {
	self = [super init];
	if (self == nil) return nil;

	// We don't want any starting value from the leadingSubject, but we do want
	// error and completion to be replayed.
    // RACReplaySubject保留error和complete
	RACReplaySubject *leadingSubject = [[RACReplaySubject replaySubjectWithCapacity:0] setNameWithFormat:@"leadingSubject"];
	RACReplaySubject *followingSubject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"followingSubject"];

	// Propagate errors and completion to everything.
    // 互相订阅 当leadingSubject发送complete给followingSubject followingSubject会发送complete给leadingSubject 两者同时结束 error同理
    // 这样任意一端complete 两端的订阅都结束
	[[leadingSubject ignoreValues] subscribe:followingSubject];
	[[followingSubject ignoreValues] subscribe:leadingSubject];

    // 订阅_leadingTerminal就相当于订阅leadingSubject
    // _followingTerminal作为订阅者 会把收到的内容转发给leadingSubject 所以实际订阅者是leadingSubject
    // leadingSubject会把值发给自己的订阅者 也就是说 _followingTerminal会把收到的值发给_leadingTerminal的订阅者 即leadingSubject的订阅者
    // 反之亦然
    // 用RACReplaySubject相当于在管道两端安装了两个转接器 这个管道就可以直接拿来使用了
    // 总结： _followingTerminal端会将收到的值通过管道传到_leadingTerminal端 反之亦然 所以称为管道
    
	_leadingTerminal = [[[RACChannelTerminal alloc] initWithValues:leadingSubject otherTerminal:followingSubject] setNameWithFormat:@"leadingTerminal"];
	_followingTerminal = [[[RACChannelTerminal alloc] initWithValues:followingSubject otherTerminal:leadingSubject] setNameWithFormat:@"followingTerminal"];

	return self;
}

@end

/// 封装了_values作为信号 _otherTerminal作为订阅者 所以既是信号又是订阅者
/// 作为信号 订阅RACChannelTerminal 实际上是订阅_values
/// 作为订阅者 实际订阅者是_otherTerminal
@implementation RACChannelTerminal

#pragma mark Lifecycle

- (id)initWithValues:(RACSignal *)values otherTerminal:(id<RACSubscriber>)otherTerminal {
	NSCParameterAssert(values != nil);
	NSCParameterAssert(otherTerminal != nil);

	self = [super init];
	if (self == nil) return nil;

	_values = values;
	_otherTerminal = otherTerminal;

	return self;
}

#pragma mark RACSignal

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	return [self.values subscribe:subscriber];
}

#pragma mark <RACSubscriber>

/// 把收到的值都发给otherTerminal
- (void)sendNext:(id)value {
	[self.otherTerminal sendNext:value];
}

- (void)sendError:(NSError *)error {
	[self.otherTerminal sendError:error];
}

- (void)sendCompleted {
	[self.otherTerminal sendCompleted];
}

- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)disposable {
	[self.otherTerminal didSubscribeWithDisposable:disposable];
}

@end
