/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"
#import "SDWebImageOperation.h"

typedef NS_OPTIONS(NSUInteger, SDWebImageDownloaderOptions) {
    
    //在低优先级的操作队列(默认)
    SDWebImageDownloaderLowPriority = 1 << 0,
    //渐进式下载(图片从上往下显示|逐行显示)
    SDWebImageDownloaderProgressiveDownload = 1 << 1,

    //通常情况下request阻止使用NSURLCache.这个选项会默认使用NSURLCache
    SDWebImageDownloaderUseNSURLCache = 1 << 2,

    //如果从NSURLCache中读取图片,会在调用完成block的时候,传递空的image或者imageData
    SDWebImageDownloaderIgnoreCachedResponse = 1 << 3,
    
    //后台进行下载,实现在后台申请额外的时间来完成请求.如果后台任务到期,操作也会被取消
    SDWebImageDownloaderContinueInBackground = 1 << 4,

    //通过设置 NSMutableURLRequest.HTTPShouldHandleCookies = YES的方式来处理存储在NSHTTPCookieStore的cookies
    SDWebImageDownloaderHandleCookies = 1 << 5,

    //允许不信任的SSL证书 一般测试的时候使用,生产环境慎用
    SDWebImageDownloaderAllowInvalidSSLCertificates = 1 << 6,
    
    //在高优先级的操作队列中下载,
    SDWebImageDownloaderHighPriority = 1 << 7,
    
    //裁剪图片
    SDWebImageDownloaderScaleDownLargeImages = 1 << 8,
};


typedef NS_ENUM(NSInteger, SDWebImageDownloaderExecutionOrder) {
    //默认,所有的下载操作将在队列中执行(FIFO先进先出)
    SDWebImageDownloaderFIFOExecutionOrder,
    //所有的下载操作将在栈中执行(LIFO后进先出)
    SDWebImageDownloaderLIFOExecutionOrder
};

//通知
//下载开始
extern NSString * _Nonnull const SDWebImageDownloadStartNotification;
//下载结束
extern NSString * _Nonnull const SDWebImageDownloadStopNotification;

//下载进度回调
typedef void(^SDWebImageDownloaderProgressBlock)(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL);
//下载完成回调
typedef void(^SDWebImageDownloaderCompletedBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, BOOL finished);

//请求头信息
typedef NSDictionary<NSString *, NSString *> SDHTTPHeadersDictionary;
typedef NSMutableDictionary<NSString *, NSString *> SDHTTPHeadersMutableDictionary;
//过滤请求头
typedef SDHTTPHeadersDictionary * _Nullable (^SDWebImageDownloaderHeadersFilterBlock)(NSURL * _Nullable url, SDHTTPHeadersDictionary * _Nullable headers);


//作为每一个下载的唯一身份标识，取消时使用.SDWebImageDownloader和我们平时开发中的下载还是又不一样的地方的，它弱化了下载过程，比较强调的是下载结果。不支持断点下载(当然这可能没有必要)。
@interface SDWebImageDownloadToken : NSObject

@property (nonatomic, strong, nullable) NSURL *url;
@property (nonatomic, strong, nullable) id downloadOperationCancelToken;

@end


/**
 * Asynchronous downloader dedicated and optimized for image loading.
 */
@interface SDWebImageDownloader : NSObject

//是否对图片进行压缩,默认YES,对图片进行压缩处理可以提高性能但是会使用大量内存
@property (assign, nonatomic) BOOL shouldDecompressImages;


//最大并发下载量
@property (assign, nonatomic) NSInteger maxConcurrentDownloads;

//当前下载数量
@property (readonly, nonatomic) NSUInteger currentDownloadCount;

//下载超时时间 ,默认 15s
@property (assign, nonatomic) NSTimeInterval downloadTimeout;

//任务执行顺序 默认FIFO
@property (assign, nonatomic) SDWebImageDownloaderExecutionOrder executionOrder;

//单例全局对象
+ (nonnull instancetype)sharedDownloader;

//认证
@property (strong, nonatomic, nullable) NSURLCredential *urlCredential;

//用户名 认证相关
@property (strong, nonatomic, nullable) NSString *username;

//密码 认证相关
@property (strong, nonatomic, nullable) NSString *password;

//实现这个block,用于过滤或者处理请求头信息
@property (nonatomic, copy, nullable) SDWebImageDownloaderHeadersFilterBlock headersFilter;

//构造函数 默认
- (nonnull instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)sessionConfiguration NS_DESIGNATED_INITIALIZER;

//设置请求头信息
- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(nullable NSString *)field;

//获取请求头信息
- (nullable NSString *)valueForHTTPHeaderField:(nullable NSString *)field;

//指定操作对象的class,需遵循SDWebImageDownloaderOperationInterface协议
- (void)setOperationClass:(nullable Class)operationClass;

//主要方法 下载图片 异步执行
- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

//根据下载token取消下载
- (void)cancel:(nullable SDWebImageDownloadToken *)token;

//设置操作队列挂起
- (void)setSuspended:(BOOL)suspended;

//取消操作队列中的所有下载操作
- (void)cancelAllDownloads;

@end
