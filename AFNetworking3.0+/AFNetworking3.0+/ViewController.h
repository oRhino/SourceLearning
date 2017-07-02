//
//  ViewController.h
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/6/28.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import <UIKit/UIKit.h>


FOUNDATION_EXPORT NSString * const ViewControllerWillRequestNotification;



@interface ViewController : UIViewController


@end

/*
#if defined(__cplusplus)    C++
#define FOUNDATION_EXTERN extern "C"
#else
#define FOUNDATION_EXTERN extern
#endif

#if TARGET_OS_WIN32  32位编译器

#if defined(NSBUILDINGFOUNDATION)
#define FOUNDATION_EXPORT FOUNDATION_EXTERN __declspec(dllexport)
#else
#define FOUNDATION_EXPORT FOUNDATION_EXTERN __declspec(dllimport)
#endif
 
#define FOUNDATION_IMPORT FOUNDATION_EXTERN __declspec(dllimport)

#else
#define FOUNDATION_EXPORT  FOUNDATION_EXTERN
#define FOUNDATION_IMPORT FOUNDATION_EXTERN
#endif
 
 */

//C++  __declspec ( extended-decl-modifier-seq ) 扩展修饰符
// 用__declspec(dllexport)，__declspec(dllimport)显式的定义dll接口给调用它的exe或dll文件，用 dllexport定义的函数不再需要（.def）文件声明这些函数接口了
