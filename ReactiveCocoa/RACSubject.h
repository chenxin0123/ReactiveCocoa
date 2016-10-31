//!
//  RACSubject.h
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/9/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSignal.h"
#import "RACSubscriber.h"

/// A subject can be thought of as a signal that you can manually control by
/// sending next, completed, and error.
///
/// They're most helpful in bridging the non-RAC world to RAC, since they let you
/// manually control the sending of events.
/// 既可以作为订阅者 也可以作为信号
/// 将收到的信号发送给自己的所有订阅者
/// 可以被多个订阅者订阅也可以订阅多个信号
@interface RACSubject : RACSignal <RACSubscriber>

/// Returns a new subject.
+ (instancetype)subject;

@end
