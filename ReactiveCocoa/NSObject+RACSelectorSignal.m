//
//  NSObject+RACSelectorSignal.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/18/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACSelectorSignal.h"
#import "EXTRuntimeExtensions.h"
#import "NSInvocation+RACTypeParsing.h"
#import "NSObject+RACDeallocating.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACObjCRuntime.h"
#import "RACSubject.h"
#import "RACTuple.h"
#import "NSObject+RACDescription.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const RACSelectorSignalErrorDomain = @"RACSelectorSignalErrorDomain";
const NSInteger RACSelectorSignalErrorMethodSwizzlingRace = 1;

static NSString * const RACSignalForSelectorAliasPrefix = @"rac_alias_";
static NSString * const RACSubclassSuffix = @"_RACSelectorSignal";
static void *RACSubclassAssociationKey = &RACSubclassAssociationKey;

static NSMutableSet *swizzledClasses() {
	static NSMutableSet *set;
	static dispatch_once_t pred;
	
	dispatch_once(&pred, ^{
		set = [[NSMutableSet alloc] init];
	});

	return set;
}

@implementation NSObject (RACSelectorSignal)

/// rac_signalForSelector的selector都会到这里来
/// 先找到对应的subject
/// 返回YES说明forwardInvocation到此为止 成功
/// 返回NO的话需要调用默认forwardInvocation实现
static BOOL RACForwardInvocation(id self, NSInvocation *invocation) {
	SEL aliasSelector = RACAliasForSelector(invocation.selector);
	RACSubject *subject = objc_getAssociatedObject(self, aliasSelector);

	Class class = object_getClass(invocation.target);
    // rac_signalForSelector的时候如果已经实现对应方法 则将其实现给aliasSelector
    // respondsToAlias说明有旧的实现 先调用原有的实现
	BOOL respondsToAlias = [class instancesRespondToSelector:aliasSelector];
	if (respondsToAlias) {
		invocation.selector = aliasSelector;
		[invocation invoke];
	}
    
    /// 没有subject 说明是普通的消息转发跟RAC无关 返回一般是NO
	if (subject == nil) return respondsToAlias;

    // 这句话触发了rac_signalForSelector的block的调用
	[subject sendNext:invocation.rac_argumentsTuple];
	return YES;
}

/// 这里的class可能是RAC生成的子类 也可能是KVO生成的子类
/// rac_signalForSelector的实现都指向了forwardInvocation:
/// 所以在这里做处理
static void RACSwizzleForwardInvocation(Class class) {
	SEL forwardInvocationSEL = @selector(forwardInvocation:);
	Method forwardInvocationMethod = class_getInstanceMethod(class, forwardInvocationSEL);

	// Preserve any existing implementation of -forwardInvocation:.
    // 已有的实现
	void (*originalForwardInvocation)(id, SEL, NSInvocation *) = NULL;
	if (forwardInvocationMethod != NULL) {
		originalForwardInvocation = (__typeof__(originalForwardInvocation))method_getImplementation(forwardInvocationMethod);
	}

	// Set up a new version of -forwardInvocation:.
	//
	// If the selector has been passed to -rac_signalForSelector:, invoke
	// the aliased method, and forward the arguments to any attached signals.
	//
	// If the selector has not been passed to -rac_signalForSelector:,
	// invoke any existing implementation of -forwardInvocation:. If there
	// was no existing implementation, throw an unrecognized selector
	// exception.
    // rac_signalForSelector的selector都会到这里来
	id newForwardInvocation = ^(id self, NSInvocation *invocation) {
        // matche
		BOOL matched = RACForwardInvocation(self, invocation);
		if (matched) return;

        // 到这里matched为NO 说明RACForwardInvocation调用失败
        // 调用原来的实现 如果原来没有实现则调用doesNotRecognizeSelector
		if (originalForwardInvocation == NULL) {
			[self doesNotRecognizeSelector:invocation.selector];
		} else {
			originalForwardInvocation(self, forwardInvocationSEL, invocation);
		}
	};

	class_replaceMethod(class, forwardInvocationSEL, imp_implementationWithBlock(newForwardInvocation), "v@:@");// id sel anInvocation
}

/// respondsToSelector的实现 主要处理对_objc_msgForward的判断
static void RACSwizzleRespondsToSelector(Class class) {
	SEL respondsToSelectorSEL = @selector(respondsToSelector:);

	// Preserve existing implementation of -respondsToSelector:.
	Method respondsToSelectorMethod = class_getInstanceMethod(class, respondsToSelectorSEL);
	BOOL (*originalRespondsToSelector)(id, SEL, SEL) = (__typeof__(originalRespondsToSelector))method_getImplementation(respondsToSelectorMethod);

	// Set up a new version of -respondsToSelector: that returns YES for methods
	// added by -rac_signalForSelector:.
	//
	// If the selector has a method defined on the receiver's actual class, and
	// if that method's implementation is _objc_msgForward, then returns whether
	// the instance has a signal for the selector.
	// Otherwise, call the original -respondsToSelector:.
	id newRespondsToSelector = ^ BOOL (id self, SEL selector) {
		Method method = rac_getImmediateInstanceMethod(class, selector);

        // _objc_msgForward_stret 不支持结构体
        // NSObjectRACSignalForSelector中使对应的selector的实现直接指向_objc_msgForward
        // 所以这里判断如果是_objc_msgForward又有一个signal(subject)就返回YES 否则使用原有实现
		if (method != NULL && method_getImplementation(method) == _objc_msgForward) {
			SEL aliasSelector = RACAliasForSelector(selector);
			if (objc_getAssociatedObject(self, aliasSelector) != nil) return YES;
		}

		return originalRespondsToSelector(self, respondsToSelectorSEL, selector);
	};

	class_replaceMethod(class, respondsToSelectorSEL, imp_implementationWithBlock(newRespondsToSelector), method_getTypeEncoding(respondsToSelectorMethod));
}

/// 让class的实例的class方法返回statedClass KVO就是这么做的
/// class是statedClass的子类
static void RACSwizzleGetClass(Class class, Class statedClass) {
	SEL selector = @selector(class);
	Method method = class_getInstanceMethod(class, selector);
	IMP newIMP = imp_implementationWithBlock(^(id self) {
		return statedClass;
	});
	class_replaceMethod(class, selector, newIMP, method_getTypeEncoding(method));
}

static void RACSwizzleMethodSignatureForSelector(Class class) {
	IMP newIMP = imp_implementationWithBlock(^(id self, SEL selector) {
		// Don't send the -class message to the receiver because we've changed
		// that to return the original class.
		Class actualClass = object_getClass(self);
		Method method = class_getInstanceMethod(actualClass, selector);
		if (method == NULL) {
            // 如果是RAC添加的方法 这里method不会为空
            // objc_msgSendSuper相当于[super xx] 这里的class是子类
			// Messages that the original class dynamically implements fall
			// here.
			//
			// Call the original class' -methodSignatureForSelector:.
			struct objc_super target = {
				.super_class = class_getSuperclass(class),
				.receiver = self,
			};
			NSMethodSignature * (*messageSend)(struct objc_super *, SEL, SEL) = (__typeof__(messageSend))objc_msgSendSuper;
			return messageSend(&target, @selector(methodSignatureForSelector:), selector);
		}

		char const *encoding = method_getTypeEncoding(method);
		return [NSMethodSignature signatureWithObjCTypes:encoding];
	});

	SEL selector = @selector(methodSignatureForSelector:);
	Method methodSignatureForSelectorMethod = class_getInstanceMethod(class, selector);
	class_replaceMethod(class, selector, newIMP, method_getTypeEncoding(methodSignatureForSelectorMethod));
}

// It's hard to tell which struct return types use _objc_msgForward, and
// which use _objc_msgForward_stret instead, so just exclude all struct, array,
// union, complex and vector return types.
static void RACCheckTypeEncoding(const char *typeEncoding) {
#if !NS_BLOCK_ASSERTIONS
	// Some types, including vector types, are not encoded. In these cases the
	// signature starts with the size of the argument frame.
	NSCAssert(*typeEncoding < '1' || *typeEncoding > '9', @"unknown method return type not supported in type encoding: %s", typeEncoding);
	NSCAssert(strstr(typeEncoding, "(") != typeEncoding, @"union method return type not supported");
	NSCAssert(strstr(typeEncoding, "{") != typeEncoding, @"struct method return type not supported");
	NSCAssert(strstr(typeEncoding, "[") != typeEncoding, @"array method return type not supported");
	NSCAssert(strstr(typeEncoding, @encode(_Complex float)) != typeEncoding, @"complex float method return type not supported");
	NSCAssert(strstr(typeEncoding, @encode(_Complex double)) != typeEncoding, @"complex double method return type not supported");
	NSCAssert(strstr(typeEncoding, @encode(_Complex long double)) != typeEncoding, @"complex long double method return type not supported");

#endif // !NS_BLOCK_ASSERTIONS
}

/// 返回的实际上是一个RACSubject
/// 调用selector会经过forwardInvocation找到对应的subject然后将参数打包成tuple 然后sendNext
static RACSignal *NSObjectRACSignalForSelector(NSObject *self, SEL selector, Protocol *protocol) {
    // selector->rac_alias_
	SEL aliasSelector = RACAliasForSelector(selector);

	@synchronized (self) {
        // 已经存在 返回
		RACSubject *subject = objc_getAssociatedObject(self, aliasSelector);
		if (subject != nil) return subject;

        // 这里返回的是class的子类
		Class class = RACSwizzleClass(self);
		NSCAssert(class != nil, @"Could not swizzle class of %@", self);

		subject = [[RACSubject subject] setNameWithFormat:@"%@ -rac_signalForSelector: %s", self.rac_description, sel_getName(selector)];
		objc_setAssociatedObject(self, aliasSelector, subject, OBJC_ASSOCIATION_RETAIN);

		[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
			[subject sendCompleted];
		}]];
        
        // 是否已有实现 包括父类的实现
		Method targetMethod = class_getInstanceMethod(class, selector);
        
		if (targetMethod == NULL) {
            // 包括父类 暂无对应的实现
			const char *typeEncoding;
			if (protocol == NULL) {
				typeEncoding = RACSignatureForUndefinedSelector(selector);
			} else {
				// Look for the selector as an optional instance method.
				struct objc_method_description methodDescription = protocol_getMethodDescription(protocol, selector, NO, YES);

				if (methodDescription.name == NULL) {
					// Then fall back to looking for a required instance
					// method.
					methodDescription = protocol_getMethodDescription(protocol, selector, YES, YES);
					NSCAssert(methodDescription.name != NULL, @"Selector %@ does not exist in <%s>", NSStringFromSelector(selector), protocol_getName(protocol));
				}

				typeEncoding = methodDescription.types;
			}

			RACCheckTypeEncoding(typeEncoding);

            // 使方法调用直接进入消息转发
			// Define the selector to call -forwardInvocation:.
			if (!class_addMethod(class, selector, _objc_msgForward, typeEncoding)) {
				NSDictionary *userInfo = @{
					NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"A race condition occurred implementing %@ on class %@", nil), NSStringFromSelector(selector), class],
					NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Invoke -rac_signalForSelector: again to override the implementation.", nil)
				};

				return [RACSignal error:[NSError errorWithDomain:RACSelectorSignalErrorDomain code:RACSelectorSignalErrorMethodSwizzlingRace userInfo:userInfo]];
			}
		} else if (method_getImplementation(targetMethod) != _objc_msgForward) {
            // 包括父类 已有实现 交换实现 rac_alias_sel对应的实现指向旧的实现
			// Make a method alias for the existing method implementation.
			const char *typeEncoding = method_getTypeEncoding(targetMethod);

			RACCheckTypeEncoding(typeEncoding);

			BOOL addedAlias __attribute__((unused)) = class_addMethod(class, aliasSelector, method_getImplementation(targetMethod), typeEncoding);
			NSCAssert(addedAlias, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(aliasSelector), class);

			// Redefine the selector to call -forwardInvocation:.
			class_replaceMethod(class, selector, _objc_msgForward, method_getTypeEncoding(targetMethod));
		}

		return subject;
	}
}

/// 返回一个SEL originalSelector -> rac_alias_originalSelector
static SEL RACAliasForSelector(SEL originalSelector) {
	NSString *selectorName = NSStringFromSelector(originalSelector);
	return NSSelectorFromString([RACSignalForSelectorAliasPrefix stringByAppendingString:selectorName]);
}

static const char *RACSignatureForUndefinedSelector(SEL selector) {
	const char *name = sel_getName(selector);
	NSMutableString *signature = [NSMutableString stringWithString:@"v@:"];

	while ((name = strchr(name, ':')) != NULL) {
		[signature appendString:@"@"];
		name++;
	}

	return signature.UTF8String;
}

/// 返回 objc_getAssociatedObject(self, RACSubclassAssociationKey);
/// 动态创建的原类的子类
static Class RACSwizzleClass(NSObject *self) {
    // 比如KVO会生成一个子类然后重写class方法 所以statedClass和baseClass可能不同
	Class statedClass = self.class;
	Class baseClass = object_getClass(self);

	// The "known dynamic subclass" is the subclass generated by RAC.
	// It's stored as an associated object on every instance that's already
	// been swizzled, so that even if something else swizzles the class of
	// this instance, we can still access the RAC generated subclass.
    // 同一个类swizzle一次就够了 所以这里直接就返回
	Class knownDynamicSubclass = objc_getAssociatedObject(self, RACSubclassAssociationKey);
	if (knownDynamicSubclass != Nil) return knownDynamicSubclass;

    // 真实类名
	NSString *className = NSStringFromClass(baseClass);

    // 如果KVO已经动态改变了子类的类型 我们就不应该再去改变
    // 这里也可能是痛一个类的不同实例
	if (statedClass != baseClass) {
		// If the class is already lying about what it is, it's probably a KVO
		// dynamic subclass or something else that we shouldn't subclass
		// ourselves.
		//
		// Just swizzle -forwardInvocation: in-place. Since the object's class
		// was almost certainly dynamically changed, we shouldn't see another of
		// these classes in the hierarchy.
		//
		// Additionally, swizzle -respondsToSelector: because the default
		// implementation may be ignorant of methods added to this class.
        // xx xx_RACSelectorSignal NSKVONotifying_xx_RACSelectorSignal
        // xx NSKVONotifying_xx_RACSelectorSignal
		@synchronized (swizzledClasses()) {
			if (![swizzledClasses() containsObject:className]) {
				RACSwizzleForwardInvocation(baseClass);
				RACSwizzleRespondsToSelector(baseClass);
                // -class 这个没必要吧 已经是这个效果了
				RACSwizzleGetClass(baseClass, statedClass);
                // metaClass +class
				RACSwizzleGetClass(object_getClass(baseClass), statedClass);
                
				RACSwizzleMethodSignatureForSelector(baseClass);
				[swizzledClasses() addObject:className];
			}
		}

		return baseClass;
	}

    // 运行到这里 statedClass跟baseClass相同
    // 新类的类名 xx_RACSelectorSignal
	const char *subclassName = [className stringByAppendingString:RACSubclassSuffix].UTF8String;
	Class subclass = objc_getClass(subclassName);

	if (subclass == nil) {
		subclass = [RACObjCRuntime createClass:subclassName inheritingFromClass:baseClass];
		if (subclass == nil) return nil;

		RACSwizzleForwardInvocation(subclass);
		RACSwizzleRespondsToSelector(subclass);

		RACSwizzleGetClass(subclass, statedClass);
		RACSwizzleGetClass(object_getClass(subclass), statedClass);

		RACSwizzleMethodSignatureForSelector(subclass);

		objc_registerClassPair(subclass);
	}

    //将这个object的isa指向新创建的subclass
	object_setClass(self, subclass);
	objc_setAssociatedObject(self, RACSubclassAssociationKey, subclass, OBJC_ASSOCIATION_ASSIGN);
	return subclass;
}


- (RACSignal *)rac_signalForSelector:(SEL)selector {
	NSCParameterAssert(selector != NULL);

	return NSObjectRACSignalForSelector(self, selector, NULL);
}

- (RACSignal *)rac_signalForSelector:(SEL)selector fromProtocol:(Protocol *)protocol {
	NSCParameterAssert(selector != NULL);
	NSCParameterAssert(protocol != NULL);

	return NSObjectRACSignalForSelector(self, selector, protocol);
}

@end
