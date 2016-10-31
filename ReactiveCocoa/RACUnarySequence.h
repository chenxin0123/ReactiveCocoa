//!
//  RACUnarySequence.h
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2013-05-01.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACSequence.h"

// Private class representing a sequence of exactly one value.
// 只包含一个值 return:返回本类实例 对应RACReturnSignal
@interface RACUnarySequence : RACSequence

@end
