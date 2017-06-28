/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageDownloader.h"
#import "SDWebImageOperation.h"

//用通知的形式暴露出关键的节点。

//任务开始
extern NSString * _Nonnull const SDWebImageDownloadStartNotification;
//接收到数据
extern NSString * _Nonnull const SDWebImageDownloadReceiveResponseNotification;
//暂停
extern NSString * _Nonnull const SDWebImageDownloadStopNotification;
//完成
extern NSString * _Nonnull const SDWebImageDownloadFinishNotification;



//描述了下载操作,如果你想自定义操作对象,你需要继承NSOperation,且遵循这个协议
@protocol SDWebImageDownloaderOperationInterface<NSObject>

//使用NSURLRequest,NSURLSession和SDWebImageDownloaderOptions初始化
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options;

//可以为每一个NSOperation自由的添加相应对象
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

///设置是否需要解压图片
- (BOOL)shouldDecompressImages;
//压缩
- (void)setShouldDecompressImages:(BOOL)value;

//设置是否需要设置凭证
- (nullable NSURLCredential *)credential;
- (void)setCredential:(nullable NSURLCredential *)value;

@end


@interface SDWebImageDownloaderOperation : NSOperation <SDWebImageDownloaderOperationInterface, SDWebImageOperation, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

//只读 请求对象
@property (strong, nonatomic, readonly, nullable) NSURLRequest *request;

//会话任务
@property (strong, nonatomic, readonly, nullable) NSURLSessionTask *dataTask;

//是否允许压缩
@property (assign, nonatomic) BOOL shouldDecompressImages;

/**
 *  Was used to determine whether the URL connection should consult the credential storage for authenticating the connection.
 *  @deprecated Not used for a couple of versions
 */
@property (nonatomic, assign) BOOL shouldUseCredentialStorage __deprecated_msg("Property deprecated. Does nothing. Kept only for backwards compatibility");


//证书 证书改变会调用 '-connection:didReceiveAuthenticationChallenge:'代理方法,
@property (nonatomic, strong, nullable) NSURLCredential *credential;

//枚举
@property (assign, nonatomic, readonly) SDWebImageDownloaderOptions options;

//文件总大小
@property (assign, nonatomic) NSInteger expectedSize;

//响应信息
@property (strong, nonatomic, nullable) NSURLResponse *response;

//建议使用构造函数
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options NS_DESIGNATED_INITIALIZER;

//添加进度block,completeBlock
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;


//不是取消任务的，而是取消任务中的响应，当任务中没有响应者的时候，任务也会被取消。
- (BOOL)cancel:(nullable id)token;

@end
