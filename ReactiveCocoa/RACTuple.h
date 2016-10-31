//!
//  RACTuple.h
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 4/12/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "metamacros.h"

@class RACSequence;

/// Creates a new tuple with the given values. At least one value must be given.
/// Values can be nil.
#define RACTuplePack(...) \
    RACTuplePack_(__VA_ARGS__)

/// Declares new object variables and unpacks a RACTuple into them.
///
/// This macro should be used on the left side of an assignment, with the
/// tuple on the right side. Nothing else should appear on the same line, and the
/// macro should not be the only statement in a conditional or loop body.
///
/// If the tuple has more values than there are variables listed, the excess
/// values are ignored.
///
/// If the tuple has fewer values than there are variables listed, the excess
/// variables are initialized to nil.
///
/// Examples
///
///   RACTupleUnpack(NSString *string, NSNumber *num) = [RACTuple tupleWithObjects:@"foo", @5, nil];
///   NSLog(@"string: %@", string);
///   NSLog(@"num: %@", num);
///
///   /* The above is equivalent to: */
///   RACTuple *t = [RACTuple tupleWithObjects:@"foo", @5, nil];
///   NSString *string = t[0];
///   NSNumber *num = t[1];
///   NSLog(@"string: %@", string);
///   NSLog(@"num: %@", num);
/// 放在等号左边 RACTuple放在右边 将RACTuple中的值赋给__VA_ARGS__
#define RACTupleUnpack(...) \
        RACTupleUnpack_(__VA_ARGS__)

/// A sentinel object that represents nils in the tuple.
///
/// It should never be necessary to create a tuple nil yourself. Just use
/// +tupleNil.
@interface RACTupleNil : NSObject <NSCopying, NSCoding>
/// A singleton instance.
+ (RACTupleNil *)tupleNil;
@end


/// A tuple is an ordered collection of objects. It may contain nils, represented
/// by RACTupleNil.
/// 元组
@interface RACTuple : NSObject <NSCoding, NSCopying, NSFastEnumeration>

@property (nonatomic, readonly) NSUInteger count;

/// These properties all return the object at that index or nil if the number of 
/// objects is less than the index.
@property (nonatomic, readonly) id first;
@property (nonatomic, readonly) id second;
@property (nonatomic, readonly) id third;
@property (nonatomic, readonly) id fourth;
@property (nonatomic, readonly) id fifth;
@property (nonatomic, readonly) id last;

/// Creates a new tuple out of the array. Does not convert nulls to nils.
/// 调用[self tupleWithObjectsFromArray:array convertNullsToNils:NO];
+ (instancetype)tupleWithObjectsFromArray:(NSArray *)array;

/// Creates a new tuple out of the array. If `convert` is YES, it also converts
/// every NSNull to RACTupleNil.
+ (instancetype)tupleWithObjectsFromArray:(NSArray *)array convertNullsToNils:(BOOL)convert;

/// Creates a new tuple with the given objects. Use RACTupleNil to represent
/// nils.
+ (instancetype)tupleWithObjects:(id)object, ... NS_REQUIRES_NIL_TERMINATION;

/// Returns the object at `index` or nil if the object is a RACTupleNil. Unlike
/// NSArray and friends, it's perfectly fine to ask for the object at an index
/// past the tuple's count - 1. It will simply return nil.
- (id)objectAtIndex:(NSUInteger)index;

/// Returns an array of all the objects. RACTupleNils are converted to NSNulls.
- (NSArray *)allObjects;

/// Appends `obj` to the receiver.
///
/// obj - The object to add to the tuple. This argument may be nil.
///
/// Returns a new tuple.
- (instancetype)tupleByAddingObject:(id)obj;

@end

@interface RACTuple (RACSequenceAdditions)

/// Returns a sequence of all the objects. RACTupleNils are converted to NSNulls.
@property (nonatomic, copy, readonly) RACSequence *rac_sequence;

@end

@interface RACTuple (ObjectSubscripting)
/// Returns the object at that index or nil if the number of objects is less
/// than the index.
- (id)objectAtIndexedSubscript:(NSUInteger)idx; 
@end

/// This and everything below is for internal use only.
///
/// See RACTuplePack() and RACTupleUnpack() instead.
///
/// metamacro_foreach(RACTuplePack_object_or_ractuplenil,, __VA_ARGS__)
/// => metamacro_foreach_cxt(metamacro_foreach_iter,PlaceHolder, RACTuplePack_object_or_ractuplenil, __VA_ARGS__)
/// => metamacro_foreach_cxtARGCOUNT(metamacro_foreach_iter,PlaceHolder, RACTuplePack_object_or_ractuplenil, __VA_ARGS__)
/// => metamacro_foreach_cxt(ARGCOUNT-1)(metamacro_foreach_iter,PlaceHolder, RACTuplePack_object_or_ractuplenil, __VA_ARGS__)
///    PlaceHolder
///    metamacro_foreach_iter(ARGCOUNT-1,RACTuplePack_object_or_ractuplenil,arg[ARGCOUNT-1])
///    => RACTuplePack_object_or_ractuplenil(ARGCOUNT-1, arg[ARGCOUNT-1])
/// => recursive...
/// metamacro_foreach(RACTuplePack_object_or_ractuplenil,,@"1",@"2",@"3",@"4")
/// => @[RACTuplePack_object_or_ractuplenil(0,@"1"),RACTuplePack_object_or_ractuplenil(1,@"2")...]

#define RACTuplePack_(...) \
    ([RACTuple tupleWithObjectsFromArray:@[ metamacro_foreach(RACTuplePack_object_or_ractuplenil,, __VA_ARGS__) ]])

#define RACTuplePack_object_or_ractuplenil(INDEX, ARG) \
    (ARG) ?: RACTupleNil.tupleNil,


/// 用法：RACTupleUnpack(NSString *str, NSNumber *num) = [RACTuple tupleWithObjects:@"foobar", @5, nil];
/// id RACTupleUnpack998_var0; id RACTupleUnpack998_var1;
/// int RACTupleUnpack_state998 = 0;
/// tagRACTupleUnpack_after_998:;__strong NSString *str = RACTupleUnpack998_var1; __strong NSNumber *num = RACTupleUnpack998_var1;
/// if (RACTupleUnpack_state != 0) RACTupleUnpack_state = 2;
/// while (RACTupleUnpack_state35 != 2)
///   if (RACTupleUnpack_state35 == 1) {
///       goto RACTupleUnpack_after998;
///   } else
///       for (; RACTupleUnpack_state998 != 1; RACTupleUnpack_state998 = 1) {
///           [RACTupleUnpackingTrampoline trampoline][ @[ [NSValue valueWithPointer:&RACTupleUnpack998_var0], [NSValue valueWithPointer:&RACTupleUnpack998_var1], ] ]
///       }

/// 以下以两个为例 假如代码在998行
/// 1. N个参数生成N个id类型变量
/// 2. 生成int类型变量RACTupleUnpack_state998
/// 3. 放一个goto语句的tag RACTupleUnpack_after_998
/// 4. 对每个参数调用RACTupleUnpack_assign(INDEX,ARG) 即：__strong NSString *str = RACTupleUnpack998_var1;
/// 5. 判断RACTupleUnpack_state的值 如果不为0 则设为2
/// 6. while成立 循环调用[RACTupleUnpackingTrampoline trampoline][array] 将1中的变量传进去赋值
/// 7. 此时RACTupleUnpack_state998为1
/// 8. 跳到3生成的tag tagRACTupleUnpack_after_998
/// 9. 再次执行第四步赋值 这时候赋值完成了
/// 10.RACTupleUnpack_state = 2
/// 11.while不成立 结束
#define RACTupleUnpack_(...) \
    metamacro_foreach(RACTupleUnpack_decl,, __VA_ARGS__) \
    \
    int RACTupleUnpack_state = 0; \
    \
    RACTupleUnpack_after: \
        ; \
        metamacro_foreach(RACTupleUnpack_assign,, __VA_ARGS__) \
        if (RACTupleUnpack_state != 0) RACTupleUnpack_state = 2; \
        \
        while (RACTupleUnpack_state != 2) \
            if (RACTupleUnpack_state == 1) { \
                goto RACTupleUnpack_after; \
            } else \
                for (; RACTupleUnpack_state != 1; RACTupleUnpack_state = 1) \
                    [RACTupleUnpackingTrampoline trampoline][ @[ metamacro_foreach(RACTupleUnpack_value,, __VA_ARGS__) ] ]

/// RACTupleUnpack_state_998
#define RACTupleUnpack_state metamacro_concat(RACTupleUnpack_state, __LINE__)
/// RACTupleUnpack_after_998 这个作为goto语句的tag
#define RACTupleUnpack_after metamacro_concat(RACTupleUnpack_after, __LINE__)
/// 这个没用
#define RACTupleUnpack_loop metamacro_concat(RACTupleUnpack_loop, __LINE__)

/// 根据代码所在行以及参数索引生成一个变量名称 如果在第998行
/// RACTupleUnpack_decl_name(8)
/// => metamacro_concat(RACTupleUnpack998 _var8)
/// => RACTupleUnpack998_var8
#define RACTupleUnpack_decl_name(INDEX) \
    metamacro_concat(metamacro_concat(RACTupleUnpack, __LINE__), metamacro_concat(_var, INDEX))

/// 声明一个id类型变量
/// RACTupleUnpack_decl(8, ARG) => __strong id RACTupleUnpack998_var8;
#define RACTupleUnpack_decl(INDEX, ARG) \
    __strong id RACTupleUnpack_decl_name(INDEX);


/// RACTupleUnpack_assign(8, ARG) => __strong ARG = RACTupleUnpack998_var8; (ARG = id arg)
#define RACTupleUnpack_assign(INDEX, ARG) \
    __strong ARG = RACTupleUnpack_decl_name(INDEX);

/// [NSValue valueWithPointer:&RACTupleUnpack998_var8], (ARG = id arg)
#define RACTupleUnpack_value(INDEX, ARG) \
    [NSValue valueWithPointer:&RACTupleUnpack_decl_name(INDEX)],

@interface RACTupleUnpackingTrampoline : NSObject

+ (instancetype)trampoline;
- (void)setObject:(RACTuple *)tuple forKeyedSubscript:(NSArray *)variables;

@end
