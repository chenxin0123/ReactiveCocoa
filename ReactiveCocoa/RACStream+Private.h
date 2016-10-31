//!
//  RACStream+Private.h
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2013-07-22.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACStream.h"

@interface RACStream ()

// Combines a list of streams using the logic of the given block.
//
// streams - The streams to combine.
// block   - An operator that combines two streams and returns a new one. The
//           returned stream should contain 2-tuples of the streams' combined
//           values.
//
// Returns a combined stream.
/// 返回值为2-tuples的流 值为嵌套类型 如:(((1), 2), 3)
+ (instancetype)join:(id<NSFastEnumeration>)streams block:(RACStream * (^)(id, id))block;

@end
