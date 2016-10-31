//!
//  RACUnit.h
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/27/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/// A unit represents an empty value.
///
/// It should never be necessary to create a unit yourself. Just use +defaultUnit.
/// 一个对象 什么都不是
@interface RACUnit : NSObject

/// A singleton instance.
+ (RACUnit *)defaultUnit;

@end
