//!
//  UITextView+RACSignalSupport.m
//  ReactiveCocoa
//
//  Created by Cody Krieger on 5/18/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "UITextView+RACSignalSupport.h"
#import "EXTScope.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "RACDelegateProxy.h"
#import "RACSignal+Operations.h"
#import "RACTuple.h"
#import <objc/runtime.h>

@implementation UITextView (RACSignalSupport)

static void RACUseDelegateProxy(UITextView *self) {
    if (self.delegate == self.rac_delegateProxy) return;

    self.rac_delegateProxy.rac_proxiedDelegate = self.delegate;
    self.delegate = (id)self.rac_delegateProxy;
}

- (RACDelegateProxy *)rac_delegateProxy {
	RACDelegateProxy *proxy = objc_getAssociatedObject(self, _cmd);
	if (proxy == nil) {
		proxy = [[RACDelegateProxy alloc] initWithProtocol:@protocol(UITextViewDelegate)];
		objc_setAssociatedObject(self, _cmd, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	return proxy;
}

/// 注意 因为调用这个方法后Delegate就变了 所以不要在这个方法之后再设置self.delegate
/// 将会替换现有的代理为新创建的RACDelegateProxy实例 原代理变成RACDelegateProxy的一个实例
/// RACDelegateProxy将会在forwardInvocation中InvocationWith原代理
/// 会立即发送当前值
- (RACSignal *)rac_textSignal {
	@weakify(self);
	RACSignal *signal = [[[[[RACSignal
		defer:^{
			@strongify(self);
			return [RACSignal return:RACTuplePack(self)];
		}]
		concat:[self.rac_delegateProxy signalForSelector:@selector(textViewDidChange:)]]
		reduceEach:^(UITextView *x) {
			return x.text;
		}]
		takeUntil:self.rac_willDeallocSignal]
		setNameWithFormat:@"%@ -rac_textSignal", self.rac_description];

	RACUseDelegateProxy(self);

	return signal;
}

@end
