// AFNetworkReachabilityManager.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFNetworkReachabilityManager.h"
#if !TARGET_OS_WATCH

#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

//网络状态发生改变的时候接收的通知
NSString * const AFNetworkingReachabilityDidChangeNotification = @"com.alamofire.networking.reachability.change";
//网络环境发生变化时会发送一个通知,携带一组状态数据,根据这个key取出网络状态
NSString * const AFNetworkingReachabilityNotificationStatusItem = @"AFNetworkingReachabilityNotificationStatusItem";

typedef void (^AFNetworkReachabilityStatusBlock)(AFNetworkReachabilityStatus status);


//枚举转换成字符串
NSString * AFStringFromNetworkReachabilityStatus(AFNetworkReachabilityStatus status) {
    switch (status) {
            //国际化
        case AFNetworkReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusUnknown:
        default:
            return NSLocalizedStringFromTable(@"Unknown", @"AFNetworking", nil);
    }
}
//私有方法可以采用这种方式 优点:
//1.在文件的最前方,容易查找
//2.使用内联函数,提高效率,防止反汇编

//根据SCNetworkReachabilityFlags转换成当前的枚举变量类型
static AFNetworkReachabilityStatus AFNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
    //不能连接到互联网
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    
    //在联网之前需要建立连接
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    //是否可以自动连接
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    //是否可以连接,在不需要用户手动设置的前提下,（用户交互一般指的是提供网络的账户和密码）
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    
    //是否可以联网的条件 1.能够到达 2.不需要建立连接或者不需要用户手动设置连接 ->就表示能够连接网络
    // 如果isReachable==YES，那么就需要判断是不是得先建立一个connection，如果需要，那就认为不可达，或者虽然需要先建立一个connection，但是不需要用户交互，那么认为也是可达的
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
    
    
    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusUnknown;
    if (isNetworkReachable == NO) {
        status = AFNetworkReachabilityStatusNotReachable;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        status = AFNetworkReachabilityStatusReachableViaWWAN;
    }
#endif
    else {
        status = AFNetworkReachabilityStatusReachableViaWiFi;
    }

    return status;
}

/**
 * Queue a status change notification for the main thread.
 *
 * This is done to ensure that the notifications are received in the same order
 * as they are sent. If notifications are sent directly, it is possible that
 * a queued notification (for an earlier status condition) is processed after
 * the later update, resulting in the listener being left in the wrong state.
 */
//接受网络状态变化的两种方式:Block,通知
//为了保证两种方式的数据统一,把这个过程封装到一个函数中.
//根据标识来处理Block和通知,保证两者同一状态
static void AFPostReachabilityStatusChange(SCNetworkReachabilityFlags flags, AFNetworkReachabilityStatusBlock block) {
    // 使用AFNetworkReachabilityStatusForFlags函数将flags转化为status，提供给下面block使用
    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusForFlags(flags);
    
    // 对于用户，可以使用KVO来观察status的变化，随后用户可以根据传过来的userInfo[AFNetworkingReachabilityNotificationStatusItem]获取到相应的status
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) {
            block(status);
        }
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSDictionary *userInfo = @{ AFNetworkingReachabilityNotificationStatusItem: @(status) };
        [notificationCenter postNotificationName:AFNetworkingReachabilityDidChangeNotification object:nil userInfo:userInfo];
    });
}

//SCNetworkReachabilityRef回调函数
static void AFNetworkReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkReachabilityFlags flags, void *info) {
    AFPostReachabilityStatusChange(flags, (__bridge AFNetworkReachabilityStatusBlock)info);
}


static const void * AFNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}

static void AFNetworkReachabilityReleaseCallback(const void *info) {
    if (info) {
        Block_release(info);
    }
}

@interface AFNetworkReachabilityManager ()

//获取网络状态的对象
@property (readonly, nonatomic, assign) SCNetworkReachabilityRef networkReachability;
//网络状态标识
@property (readwrite, nonatomic, assign) AFNetworkReachabilityStatus networkReachabilityStatus;
//Block
@property (readwrite, nonatomic, copy) AFNetworkReachabilityStatusBlock networkReachabilityStatusBlock;

@end

@implementation AFNetworkReachabilityManager

+ (instancetype)sharedManager {
    static AFNetworkReachabilityManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [self manager];
    });

    return _sharedManager;
}

+ (instancetype)managerForDomain:(NSString *)domain {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);

    AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    
    CFRelease(reachability);

    return manager;
}

+ (instancetype)managerForAddress:(const void *)address {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);
    AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];

    CFRelease(reachability);
    
    return manager;
}

+ (instancetype)manager
{
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000) || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 101100)
    //IPV_6
    struct sockaddr_in6 address;
    bzero(&address, sizeof(address));
    address.sin6_len = sizeof(address);
    address.sin6_family = AF_INET6;
#else
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
#endif
    return [self managerForAddress:&address];
}

- (instancetype)initWithReachability:(SCNetworkReachabilityRef)reachability {
    self = [super init];
    if (!self) {
        return nil;
    }
    _networkReachability = CFRetain(reachability);
    self.networkReachabilityStatus = AFNetworkReachabilityStatusUnknown;

    return self;
}
//不可用 一个error
- (instancetype)init NS_UNAVAILABLE
{
    return nil;
}

- (void)dealloc {
    
    [self stopMonitoring];
    
    if (_networkReachability != NULL) {
        CFRelease(_networkReachability);
    }
}

#pragma mark -

//getter
- (BOOL)isReachable {
    return [self isReachableViaWWAN] || [self isReachableViaWiFi];
}

- (BOOL)isReachableViaWWAN {
    return self.networkReachabilityStatus == AFNetworkReachabilityStatusReachableViaWWAN;
}

- (BOOL)isReachableViaWiFi {
    return self.networkReachabilityStatus == AFNetworkReachabilityStatusReachableViaWiFi;
}

#pragma mark -
//Core Code
- (void)startMonitoring {
    // 先停止之前的网络监听
    [self stopMonitoring];
    
    // networkReachability表示的是需要检测的网络地址的句柄
    if (!self.networkReachability) {
        return;
    }

    __weak __typeof(self)weakSelf = self;
    // 根据网络状态status来设置网络状态监听的回调函数callback
    AFNetworkReachabilityStatusBlock callback = ^(AFNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;

        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }

    };
    /** context是一个结构体
     typedef struct {
     // 创建一个SCNetworkReachabilityContext结构体时，需要调用SCDynamicStore的创建函数，而此创建函数会根据version来创建出不同的结构体，SCNetworkReachabilityContext对应的version是0
     CFIndex        version;
     // 下面两个block（release和retain）的参数就是info，此处表示的是网络状态处理的回调函数
     void *        __nullable info;
     // 该retain block用于对info进行retain，下面那个AFNetworkReachabilityRetainCallback核心就是调用了Block_copy（用于retain一个block函数，即在堆空间新建或直接引用一个block拷贝）
     const void    * __nonnull (* __nullable retain)(const void *info);
     // 该release block用于对info进行release，下面那个AFNetworkReachabilityReleaseCallback核心就是调用了Block_release（用于release一个block函数，即将block从堆空间移除或移除相应引用）
     void        (* __nullable release)(const void *info);
     // 提供info的description，此处调用为NULL
     CFStringRef    __nonnull (* __nullable copyDescription)(const void *info);
     } SCNetworkReachabilityContext;
     */
    
    //创建上下文
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, AFNetworkReachabilityRetainCallback, AFNetworkReachabilityReleaseCallback, NULL};
    
    /**
     // 给客户端指定对应target（该参数和需要检测网络状况的地址有一定关联，此处使用的是self.networkReachability），然后当这个target的网络状态变化时，告之SCNetworkReachabilityCallBack对象callout处理（此处使用的是AFNetworkReachabilityCallback），另外callout中使用到的参数包括target和context提供的info。
     Boolean
     SCNetworkReachabilitySetCallback    (
     SCNetworkReachabilityRef                                        target,
     SCNetworkReachabilityCallBack    __nullable    callout,
     SCNetworkReachabilityContext    * __nullable    context
     )                __OSX_AVAILABLE_STARTING(__MAC_10_3,__IPHONE_2_0);
     */
    
    //设置回调
    SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
    
    /**
     此处表示在main RunLoop中以kCFRunLoopCommonModes形式处理self.networkingReachability
     */
    //加入RunLoop Main
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    
    // 在后台检测self.networkingReachability的网络状态，并使用SCNetworkReachabilityGetFlags函数返回产生的flag，注意此处flag表示的就是网络的状态，后面会详细介绍每种flag对应的状态是什么
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(self.networkReachability, &flags)) {
             // AFPostReachabilityStatusChange函数就是先将flags转化为对应的AFNetworkReachabilityStatus变量，然后给我们的callback处理，后面会详解此函数
            AFPostReachabilityStatusChange(flags, callback);
        }
    });
}
//停止监听
- (void)stopMonitoring {
    if (!self.networkReachability) {
        return;
    }

    SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

#pragma mark -

- (NSString *)localizedNetworkReachabilityStatusString {
    return AFStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}

#pragma mark -

- (void)setReachabilityStatusChangeBlock:(void (^)(AFNetworkReachabilityStatus status))block {
    self.networkReachabilityStatusBlock = block;
}

#pragma mark - NSKeyValueObserving
//注册键值监听依赖
//在实际开发中，往往一个属性是由其他属性一起决定的。例如一个人的fullName是由firstName和lastName决定的。或者说一个集合类型的属性，由其内容元素变化引起改变。这些属性与属性之间，集合与元素之间都存在依赖。因此这种依赖也是可以用KVO来进行通知变化的，以保证数据一致性。
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }

    return [super keyPathsForValuesAffectingValueForKey:key];
}

@end
#endif
