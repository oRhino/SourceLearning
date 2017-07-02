//
//  UIViewController+ViewDidLoad.m
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/6/28.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "UIViewController+ViewDidLoad.h"
#import <objc/runtime.h>

typedef id   (* _IMP)(id,SEL,...);
typedef void (* VIMP)(id,SEL,...);

@implementation UIViewController (ViewDidLoad)

//IMP就是Implementation的缩写，顾名思义，它是指向一个方法实现的指针，每一个方法都有一个对应的IMP
//Xcode -> Enable Strict Checking of objc_msgSend Calls 默认YES改为NO
//默认:这种情况下IMP被定义为无参数无返回值的函数 重新定义一个和有参数的IMP指针相同的指针类型，在获取IMP时把它强转为此类型。这样运用IMP指针后，就不需要额外的给ViewController写新的方法

/*
 Swizzling的两种实现
1. runtime交换方法
2. IMP指针
 */


#if 0
+ (void)load{
    //保证交换方法只执行一次
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        //获取原有的方法
        Method oldMethod = class_getInstanceMethod(self, @selector(viewDidLoad));
        //获取自己添加的方法
        Method newMethod = class_getInstanceMethod(self, @selector(viewDidLoaded));
        //互换两个方法的实现
        method_exchangeImplementations(oldMethod, newMethod);
    });
}
#else
+ (void)load{
    //保证交换方法只执行一次
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        //获取原始方法
        Method viewDidLoad = class_getInstanceMethod(self, @selector(viewDidLoad));
        //获取原始方法的实现
        VIMP methodImplement = (VIMP)method_getImplementation(viewDidLoad);
        
        //重新定义方法的实现
        method_setImplementation(viewDidLoad, imp_implementationWithBlock(^(id target,SEL action){
            //调用原有代码
            methodImplement(target,@selector(viewDidLoad));
            //添加新的实现
            NSLog(@"IMP_%@:view didloaded!",self);
        }));
            
    });
}


#endif

- (void)viewDidLoaded{
    //调用原来的方法
    [self viewDidLoaded];
    NSLog(@"exchangeIMP_%@:view didloaded!",self);
}


@end
