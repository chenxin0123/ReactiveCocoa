//!
//  NSUserDefaults+RACSupport.m
//  ReactiveCocoa
//
//  Created by Matt Diephouse on 12/19/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSUserDefaults+RACSupport.h"
#import "EXTScope.h"
#import "NSNotificationCenter+RACSupport.h"
#import "NSObject+RACDeallocating.h"
#import "RACChannel.h"
#import "RACScheduler.h"
#import "RACSignal+Operations.h"

@implementation NSUserDefaults (RACSupport)

- (RACChannelTerminal *)rac_channelTerminalForKey:(NSString *)key {
	RACChannel *channel = [RACChannel new];
	
	RACScheduler *scheduler = [RACScheduler scheduler];
	__block BOOL ignoreNextValue = NO;
	
    // 订阅 这样followingTerminal的订阅者可以收到变化的值
    // filter ignoreNextValue 防止循环发送值
	@weakify(self);
	[[[[[[[NSNotificationCenter.defaultCenter
		rac_addObserverForName:NSUserDefaultsDidChangeNotification object:self]
		map:^(id _) {
			@strongify(self);
			return [self objectForKey:key];
		}]
		startWith:[self objectForKey:key]]
		// Don't send values that were set on the other side of the terminal.
		filter:^ BOOL (id _) {
			if (RACScheduler.currentScheduler == scheduler && ignoreNextValue) {
				ignoreNextValue = NO;
				return NO;
			}
			return YES;
		}]
		distinctUntilChanged]
		takeUntil:self.rac_willDeallocSignal]
		subscribe:channel.leadingTerminal];
	
    // 这样可以收到外面收到的值
	[[channel.leadingTerminal
		deliverOn:scheduler]
		subscribeNext:^(id value) {
			@strongify(self);
			ignoreNextValue = YES;
			[self setObject:value forKey:key];
		}];
	
	return channel.followingTerminal;
}

@end
