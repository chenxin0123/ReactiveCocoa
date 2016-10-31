//!
//  RACDynamicSignal.h
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2013-10-10.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACSignal.h"

// A private `RACSignal` subclasses that implements its subscription behavior
// using a block.
// 保存didSubscribe 这个didSubscribe每次被订阅都会被调用
@interface RACDynamicSignal : RACSignal

+ (RACSignal *)createSignal:(RACDisposable * (^)(id<RACSubscriber> subscriber))didSubscribe;

@end
