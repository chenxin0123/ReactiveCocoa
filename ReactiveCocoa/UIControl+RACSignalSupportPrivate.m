//!
//  UIControl+RACSignalSupportPrivate.m
//  ReactiveCocoa
//
//  Created by Uri Baghin on 06/08/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UIControl+RACSignalSupportPrivate.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACLifting.h"
#import "RACChannel.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSignal+Operations.h"
#import "UIControl+RACSignalSupport.h"

@implementation UIControl (RACSignalSupportPrivate)

/// 创建一个新的RACChannel 返回channel.leadingTerminal
/// 一旦controlEvents触发 则返回valueForKey:key的值给channel.leadingTerminal的订阅者
/// 一旦channel.leadingTerminal收到值则触发setValue:forKey:
- (RACChannelTerminal *)rac_channelForControlEvents:(UIControlEvents)controlEvents key:(NSString *)key nilValue:(id)nilValue {
	NSCParameterAssert(key.length > 0);
	key = [key copy];
	RACChannel *channel = [[RACChannel alloc] init];

	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[channel.followingTerminal sendCompleted];
	}]];

    
	RACSignal *eventSignal = [[[self
		rac_signalForControlEvents:controlEvents]
		mapReplace:key]
		takeUntil:[[channel.followingTerminal
			ignoreValues]
			catchTo:RACSignal.empty]];
    
    // 将值发出去 replaylast
	[[self
		rac_liftSelector:@selector(valueForKey:) withSignals:eventSignal, nil]
		subscribe:channel.followingTerminal];

    // 用收进来的值setValue:forKey:
	RACSignal *valuesSignal = [channel.followingTerminal
		map:^(id value) {
			return value ?: nilValue;
		}];
	[self rac_liftSelector:@selector(setValue:forKey:) withSignals:valuesSignal, [RACSignal return:key], nil];

	return channel.leadingTerminal;
}

@end
