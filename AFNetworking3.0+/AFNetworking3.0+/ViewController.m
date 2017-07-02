//
//  ViewController.m
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/6/28.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "ViewController.h"
#import "UIViewController+ViewDidLoad.h"
#import "AFNetworking.h"

NSString * const ViewControllerWillRequestNotification = @"ViewControllerWillRequest";
#define MARCHO @"ViewControllerWillRequest"


static inline NSString * ContentTypeForPathExtension(NSString *extension) {
    NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
    if (!contentType) {
        return @"application/octet-stream";
    } else {
        return contentType;
    }
}



static inline void testNSPropertyPlistSerializationWithObj(id obj){
    
    NSDictionary *dict = @{
                           @"firstName":@"zhangsan",
                           @"lastName":@"allen",
                           @"age":@(24),
                           @"sex":@(YES),
                           @"like":@[@"apple",@"sing",@"playGames"]
                           };
    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (error) {
        NSLog(@"error:%@",error.localizedDescription);
        return;
    }
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSLog(@"%@",path);
    
    [data writeToFile:[NSString stringWithFormat:@"%@/users",path] atomically:YES];
    
    
    
    NSDictionary *newDict =  [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    
    NSLog(@"%@",newDict);
    
    
}




@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self marco];
    
//    //200 - 299
//    NSIndexSet *set = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
//    NSLog(@"%@",set);
    
    [self testUrlQuery];
    
    testNSPropertyPlistSerializationWithObj(nil);
    
    //en
    [[NSLocale preferredLanguages] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSLog(@"%@",obj);
    }];
    NSLog(@"%@",
    [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)",
     [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey],//bundle id
     [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], //app版本
     [[UIDevice currentDevice] model], //设备
     [[UIDevice currentDevice] systemVersion], //系统版本
     [[UIScreen mainScreen] scale]]//屏幕scale
          );
    
    NSData *data = [[NSString stringWithFormat:@"zhangsan:123456"] dataUsingEncoding:NSUTF8StringEncoding];
    
    NSLog(@"%@",[data base64EncodedStringWithOptions:0]);
    
    
    //video/mp4___audio/mpeg___image/png___image/gif___video/quicktime
    NSLog(@"%@___%@___%@___%@___%@",
          ContentTypeForPathExtension(@"mp4"),
          ContentTypeForPathExtension(@"mp3"),
          ContentTypeForPathExtension(@"png"),
          ContentTypeForPathExtension(@"gif"),
          ContentTypeForPathExtension(@"mov")
          );
    
}


- (void)marco{
    
    NSParameterAssert(1); //表达式为假的时候,Crash
    
    
//    FOUNDATFOUNDATION_EXPORT在c文件编译下是和extern等同，在c++文件编译下是和extern “C”等同，在32位机的环境下又是另外编译情况，在兼容性方面，FOUNDATION_EXPORT做的会更好。ION_EXPORT在c文件编译下是和extern等同，在c++文件编译下是和extern “C”等同，在32位机的环境下又是另外编译情况，在兼容性方面，FOUNDATION_EXPORT做的会更好。
    NSString *string = @"ViewControllerWillRequest";
    if (string == ViewControllerWillRequestNotification) {
        NSLog(@"FOUNDATION_EXPORT: %p == %p",string,ViewControllerWillRequestNotification);
    }
    if ([string isEqualToString:ViewControllerWillRequestNotification]) {
        NSLog(@"FOUNDATION_EXPORT:isEqualToString");
    }
    //警告
    if (string == MARCHO) {
        //Direct comparison of a string literal has undefined behavior
        NSLog(@"#define:%p == %p",string,MARCHO);
    }
    if ([string isEqualToString:MARCHO]) {
        NSLog(@"#define isEqualToString");
    }
    
}

- (void)testUrlQuery{
    
    
//    static NSString * const kAFCharactersGeneralDelimitersToEncode = @":#[]@"; // does not include "?" or "/" due to RFC 3986 - Section 3.4
//    static NSString * const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";
//
//    //allowed in an URL's query component
//    NSMutableCharacterSet * allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
//
//    NSLog(@"allow:%@",allowedCharacterSet);
//    [allowedCharacterSet removeCharactersInString:[kAFCharactersGeneralDelimitersToEncode stringByAppendingString:kAFCharactersSubDelimitersToEncode]];
//    NSLog(@"allow:%@",allowedCharacterSet);
    
    
    NSString *string = @"看我😄,你在🌹害怕什么,跟我做,你的🐑娃娃";
    NSRange range = NSMakeRange(0, 3);
    range = [string rangeOfComposedCharacterSequencesForRange:range];
    NSLog(@"range:%ld,%ld",range.location,range.length);//(0,4)
    NSString *face = @"😄"; //2
    NSLog(@"%ld",face.length);
    //www.wangbadan.com/save?login %3D 33234 %2A %26 76 %26 name %3D %5B %40 %21 ...ssdd%29
    
    NSString *a =AFPercentEscapedStringFromString(@"www.wangbadan.com/save?login=33234*&76&name=[@!...ssdd)");
    NSLog(@"%@\n%@",a,a.stringByRemovingPercentEncoding);

    NSLog(@"%@",AFPercentEscapedStringFromString(@"URL编码"));
    
    /*
     =   %3D
     *   %2A
     &   %26
     [   %5B
     @   %40
     !   %21
     */
    
    NSMutableArray *acceptLanguagesComponents = [NSMutableArray array];
    [[NSLocale preferredLanguages] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        float q = 1.0f - (idx * 0.1f);
        [acceptLanguagesComponents addObject:[NSString stringWithFormat:@"%@;q=%0.1g", obj, q]];
        *stop = q <= 0.5f;
    }];
    NSMutableDictionary *dict = [[NSMutableDictionary alloc]init];
    [dict setValue:[acceptLanguagesComponents componentsJoinedByString:@", "] forKey:@"Accept-Language"];
    NSLog(@"%@",dict);
    
    
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}





@end
