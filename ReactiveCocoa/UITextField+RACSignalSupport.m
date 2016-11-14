//!
//  UITextField+RACSignalSupport.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/17/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "UITextField+RACSignalSupport.h"
#import "EXTKeyPathCoding.h"
#import "EXTScope.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "RACSignal+Operations.h"
#import "UIControl+RACSignalSupport.h"
#import "UIControl+RACSignalSupportPrivate.h"

@implementation UITextField (RACSignalSupport)

/// 监听text值 订阅的时候会立刻返回当前值
- (RACSignal *)rac_textSignal {
	@weakify(self);
	return [[[[[RACSignal
		defer:^{
			@strongify(self);
			return [RACSignal return:self];
		}]
		concat:[self rac_signalForControlEvents:UIControlEventAllEditingEvents]]
		map:^(UITextField *x) {
			return x.text;
		}]
		takeUntil:self.rac_willDeallocSignal]
		setNameWithFormat:@"%@ -rac_textSignal", self.rac_description];
}

/// 返回一个管道一端 既可以监听值的变化 又可以订阅其他值来setValueForKey 不会立刻返回当前值
- (RACChannelTerminal *)rac_newTextChannel {
	return [self rac_channelForControlEvents:UIControlEventAllEditingEvents key:@keypath(self.text) nilValue:@""];
}

@end
