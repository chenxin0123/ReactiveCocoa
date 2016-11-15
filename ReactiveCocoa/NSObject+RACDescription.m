//!
//  NSObject+RACDescription.m
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2013-05-13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACDescription.h"
#import "RACTuple.h"

/// 需要设置RAC_DEBUG_SIGNAL_NAMES才生效
/// Xcode –> Product –>Scheme –> Edit Schemt –> Arguments ,添加新的Environment variable s, RAC_DEBUG_SIGNAL_NAMES,值设为1即可
@implementation NSObject (RACDescription)

- (NSString *)rac_description {
	if (getenv("RAC_DEBUG_SIGNAL_NAMES") != NULL) {
		return [[NSString alloc] initWithFormat:@"<%@: %p>", self.class, self];
	} else {
		return @"(description skipped)";
	}
}

@end

@implementation NSValue (RACDescription)

- (NSString *)rac_description {
	return self.description;
}

@end

@implementation NSString (RACDescription)

- (NSString *)rac_description {
	return self.description;
}

@end

@implementation RACTuple (RACDescription)

- (NSString *)rac_description {
	if (getenv("RAC_DEBUG_SIGNAL_NAMES") != NULL) {
		return self.allObjects.description;
	} else {
		return @"(description skipped)";
	}
}

@end
