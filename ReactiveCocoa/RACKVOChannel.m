//!
//  RACKVOChannel.m
//  ReactiveCocoa
//
//  Created by Uri Baghin on 27/12/2012.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACKVOChannel.h"
#import "EXTScope.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACKVOWrapper.h"
#import "NSString+RACKeyPathUtilities.h"
#import "RACChannel.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSignal+Operations.h"

// Key for the array of RACKVOChannel's additional thread local
// data in the thread dictionary.
static NSString * const RACKVOChannelDataDictionaryKey = @"RACKVOChannelKey";

// Wrapper class for additional thread local data.
@interface RACKVOChannelData : NSObject

// The flag used to ignore updates the channel itself has triggered.
@property (nonatomic, assign) BOOL ignoreNextUpdate;

// A pointer to the owner of the data. Only use this for pointer comparison,
// never as an object reference.
// 指向+ (instancetype)dataForChannel:(RACKVOChannel *)channel;中的channel
@property (nonatomic, assign) void *owner;

+ (instancetype)dataForChannel:(RACKVOChannel *)channel;

@end


/** 例子
     RACChannelTerminal *channelA = RACChannelTo(self, valueA);
     RACChannelTerminal *channelB = RACChannelTo(self, valueB);
     [[channelA map:^id(NSString *value) {
         if ([value isEqualToString:@"西"]) {
             return @"东";
         }
         return value;
     }] subscribe:channelB];
     [[channelB map:^id(NSString *value) {
         if ([value isEqualToString:@"左"]) {
             return @"右";
         }
         return value;
     }] subscribe:channelA];
     [[RACObserve(self, valueA) filter:^BOOL(id value) {
         return value ? YES : NO;
     }] subscribeNext:^(NSString* x) {
         NSLog(@"你向%@", x);
     }];
     [[RACObserve(self, valueB) filter:^BOOL(id value) {
         return value ? YES : NO;
     }] subscribeNext:^(NSString* x) {
         NSLog(@"他向%@", x);
     }];
     self.valueA = @"西";
     self.valueB = @"左";
 
 2015-08-15 20:14:46.544 Test[2440:99901] 你向西
 2015-08-15 20:14:46.544 Test[2440:99901] 他向东
 2015-08-15 20:14:46.545 Test[2440:99901] 他向左
 2015-08-15 20:14:46.545 Test[2440:99901] 你向右
 
 */

@interface RACKVOChannel ()

// The object whose key path the channel is wrapping.
@property (atomic, weak) NSObject *target;

// The key path the channel is wrapping.
@property (nonatomic, copy, readonly) NSString *keyPath;

// Returns the existing thread local data container or nil if none exists.
@property (nonatomic, strong, readonly) RACKVOChannelData *currentThreadData;

// Creates the thread local data container for the channel.
- (void)createCurrentThreadData;

// Destroy the thread local data container for the channel.
- (void)destroyCurrentThreadData;

@end

@implementation RACKVOChannel

#pragma mark Properties

/// 返回对应的RACKVOChannelData 无则返回nil
- (RACKVOChannelData *)currentThreadData {
	NSMutableArray *dataArray = NSThread.currentThread.threadDictionary[RACKVOChannelDataDictionaryKey];

	for (RACKVOChannelData *data in dataArray) {
		if (data.owner == (__bridge void *)self) return data;
	}

	return nil;
}

#pragma mark Lifecycle

- (id)initWithTarget:(__weak NSObject *)target keyPath:(NSString *)keyPath nilValue:(id)nilValue {
	NSCParameterAssert(keyPath.rac_keyPathComponents.count > 0);

	NSObject *strongTarget = target;

	self = [super init];
	if (self == nil) return nil;

	_target = target;
	_keyPath = [keyPath copy];

	[self.leadingTerminal setNameWithFormat:@"[-initWithTarget: %@ keyPath: %@ nilValue: %@] -leadingTerminal", target, keyPath, nilValue];
	[self.followingTerminal setNameWithFormat:@"[-initWithTarget: %@ keyPath: %@ nilValue: %@] -followingTerminal", target, keyPath, nilValue];

    // 两端都结束
	if (strongTarget == nil) {
		[self.leadingTerminal sendCompleted];
		return self;
	}

	// Observe the key path on target for changes and forward the changes to the
	// terminal.
	//
	// Intentionally capturing `self` strongly in the blocks below, so the
	// channel object stays alive while observing.
    // 观察keypath值的变化 发给leadingTerminal
	RACDisposable *observationDisposable = [strongTarget rac_observeKeyPath:keyPath options:NSKeyValueObservingOptionInitial observer:nil block:^(id value, NSDictionary *change, BOOL causedByDealloc, BOOL affectedOnlyLastComponent) {
		// If the change wasn't triggered by deallocation, only affects the last
		// path component, and ignoreNextUpdate is set, then it was triggered by
		// this channel and should not be forwarded.
        // ignoreNextUpdate用来标志是否忽略下一次的变化
        // 因为RACChannelTo将followingTerminal返回 followingTerminal订阅得到的值会引发target.keypath的值的变化 keypath的值的变化又会发给followingTerminal的订阅者 这是没有必要的
		if (!causedByDealloc && affectedOnlyLastComponent && self.currentThreadData.ignoreNextUpdate) {
			[self destroyCurrentThreadData];
			return;
		}

        // KVO变化的值会被发给followingTerminal的订阅者
        // RACChannelTo宏把followingTerminal暴露出来 这样只要订阅followingTerminal就能收到变化的值了
		[self.leadingTerminal sendNext:value];
	}];

	NSString *keyPathByDeletingLastKeyPathComponent = keyPath.rac_keyPathByDeletingLastKeyPathComponent;
	NSArray *keyPathComponents = keyPath.rac_keyPathComponents;
	NSUInteger keyPathComponentsCount = keyPathComponents.count;
	NSString *lastKeyPathComponent = keyPathComponents.lastObject;

	// Update the value of the property with the values received.
    
    
	[[self.leadingTerminal
		finally:^{
			[observationDisposable dispose];
		}]
		subscribeNext:^(id x) {
			// Check the value of the second to last key path component. Since the
			// channel can only update the value of a property on an object, and not
			// update intermediate objects, it can only update the value of the whole
			// key path if this object is not nil.
            // 这里收到的是followingTerminal作为订阅者收到的值 赋给target属性
            // target.son.school -> target.son target.son -> target
			NSObject *object = (keyPathComponentsCount > 1 ? [self.target valueForKeyPath:keyPathByDeletingLastKeyPathComponent] : self.target);
			if (object == nil) return;

			// Set the ignoreNextUpdate flag before setting the value so this channel
			// ignores the value in the subsequent -didChangeValueForKey: callback.
			[self createCurrentThreadData];
			self.currentThreadData.ignoreNextUpdate = YES;

			[object setValue:x ?: nilValue forKey:lastKeyPathComponent];
		} error:^(NSError *error) {
			NSCAssert(NO, @"Received error in %@: %@", self, error);

			// Log the error if we're running with assertions disabled.
			NSLog(@"Received error in %@: %@", self, error);
		}];

	// Capture `self` weakly for the target's deallocation disposable, so we can
	// freely deallocate if we complete before then.
	@weakify(self);

    // 对象释放 结束这个管道
	[strongTarget.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		@strongify(self);
        // 结束任意一端
		[self.leadingTerminal sendCompleted];
		self.target = nil;
	}]];

	return self;
}

/// 将self对应的RACKVOChannelData放入NSThread.currentThread.threadDictionary[RACKVOChannelDataDictionaryKey]
- (void)createCurrentThreadData {
	NSMutableArray *dataArray = NSThread.currentThread.threadDictionary[RACKVOChannelDataDictionaryKey];
	if (dataArray == nil) {
		dataArray = [NSMutableArray array];
		NSThread.currentThread.threadDictionary[RACKVOChannelDataDictionaryKey] = dataArray;
		[dataArray addObject:[RACKVOChannelData dataForChannel:self]];
		return;
	}

	for (RACKVOChannelData *data in dataArray) {
		if (data.owner == (__bridge void *)self) return;
	}

	[dataArray addObject:[RACKVOChannelData dataForChannel:self]];
}

/// 移除self对应的RACKVOChannelData
- (void)destroyCurrentThreadData {
	NSMutableArray *dataArray = NSThread.currentThread.threadDictionary[RACKVOChannelDataDictionaryKey];
	NSUInteger index = [dataArray indexOfObjectPassingTest:^ BOOL (RACKVOChannelData *data, NSUInteger idx, BOOL *stop) {
		return data.owner == (__bridge void *)self;
	}];

	if (index != NSNotFound) [dataArray removeObjectAtIndex:index];
}

@end

@implementation RACKVOChannel (RACChannelTo)

- (RACChannelTerminal *)objectForKeyedSubscript:(NSString *)key {
	NSCParameterAssert(key != nil);

	RACChannelTerminal *terminal = [self valueForKey:key];
	NSCAssert([terminal isKindOfClass:RACChannelTerminal.class], @"Key \"%@\" does not identify a channel terminal", key);

	return terminal;
}

- (void)setObject:(RACChannelTerminal *)otherTerminal forKeyedSubscript:(NSString *)key {
	NSCParameterAssert(otherTerminal != nil);

    // 相当于给管道加一个口 保留原来的端的功能 只是原来的这个口被隐藏了
	RACChannelTerminal *selfTerminal = [self objectForKeyedSubscript:key];
    // 旧端会把收到的值发给另一端的订阅者 所以这里旧端订阅新端 新端值会发送给旧端 旧端再把值发给另一端的订阅者
	[otherTerminal subscribe:selfTerminal];
    // 另一端会把收到的值发给旧端的订阅者 所以这里新端订阅旧端 这样旧端收到另一端的值后就会将值发给新端 新端再发给自己的订阅者
	[[selfTerminal skip:1] subscribe:otherTerminal];
}

@end

@implementation RACKVOChannelData

+ (instancetype)dataForChannel:(RACKVOChannel *)channel {
	RACKVOChannelData *data = [[self alloc] init];
	data->_owner = (__bridge void *)channel;
	return data;
}

@end
