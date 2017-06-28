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


//SDWebImageDownloaderOperation的主要任务是把一张图片从服务器下载到内存中
//1.NSOperation有两个方法：main() 和 start()。如果想使用同步，那么最简单方法的就是把逻辑写在main()中，使用异步，需要把逻辑写到start()中，然后加入到队列之中。
//2.大家有没有想过NSOperation什么时候执行呢？按照正常想法，难道要我们自己手动调用main() 和 start()吗？这样肯定也是行的。当调用start()的时候，默认的是在当前线程执行同步操作，如果是在主线程调用了，那么必然会导致程序死锁。另外一种方法就是加入到operationQueue中，operationQueue会尽快执行NSOperation，如果operationQueue是同步的，那么它会等到NSOperation的isFinished等于YES后，在执行下一个任务，如果是异步的，通过设置maxConcurrentOperationCount来控制同事执行的最大操作，某个操作完成后，继续其他的操作。
//3.并不是调用了canche就一定取消了，如果NSOperation没有执行，那么就会取消，如果执行了，只会将isCancelled设置为YES。所以，在我们的操作中，我们应该在每个操作开始前，或者在每个有意义的实际操作完成后，先检查下这个属性是不是已经设置为YES。如果是YES，则后面操作都可以不用在执行了。
/**
 Describes a downloader operation. If one wants to use a custom downloader op, it needs to inherit from `NSOperation` and conform to this protocol
 */
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
- (void)setShouldDecompressImages:(BOOL)value;

//设置是否需要设置凭证
- (nullable NSURLCredential *)credential;
- (void)setCredential:(nullable NSURLCredential *)value;

@end


@interface SDWebImageDownloaderOperation : NSOperation <SDWebImageDownloaderOperationInterface, SDWebImageOperation, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

/**
 * The request used by the operation's task.
 */
@property (strong, nonatomic, readonly, nullable) NSURLRequest *request;

/**
 * The operation's task
 */
@property (strong, nonatomic, readonly, nullable) NSURLSessionTask *dataTask;


@property (assign, nonatomic) BOOL shouldDecompressImages;

/**
 *  Was used to determine whether the URL connection should consult the credential storage for authenticating the connection.
 *  @deprecated Not used for a couple of versions
 */
@property (nonatomic, assign) BOOL shouldUseCredentialStorage __deprecated_msg("Property deprecated. Does nothing. Kept only for backwards compatibility");

/**
 * The credential used for authentication challenges in `-connection:didReceiveAuthenticationChallenge:`.
 *
 * This will be overridden by any shared credentials that exist for the username or password of the request URL, if present.
 */
@property (nonatomic, strong, nullable) NSURLCredential *credential;

/**
 * The SDWebImageDownloaderOptions for the receiver.
 */
@property (assign, nonatomic, readonly) SDWebImageDownloaderOptions options;

/**
 * The expected size of data.
 */
@property (assign, nonatomic) NSInteger expectedSize;

/**
 * The response returned by the operation's connection.
 */
@property (strong, nonatomic, nullable) NSURLResponse *response;

/**
 *  Initializes a `SDWebImageDownloaderOperation` object
 *
 *  @see SDWebImageDownloaderOperation
 *
 *  @param request        the URL request
 *  @param session        the URL session in which this operation will run
 *  @param options        downloader options
 *
 *  @return the initialized instance
 */
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options NS_DESIGNATED_INITIALIZER;

/**
 *  Adds handlers for progress and completion. Returns a tokent that can be passed to -cancel: to cancel this set of
 *  callbacks.
 *
 *  @param progressBlock  the block executed when a new chunk of data arrives.
 *                        @note the progress block is executed on a background queue
 *  @param completedBlock the block executed when the download is done.
 *                        @note the completed block is executed on the main queue for success. If errors are found, there is a chance the block will be executed on a background queue
 *
 *  @return the token to use to cancel this set of handlers
 */
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

/**
 *  Cancels a set of callbacks. Once all callbacks are canceled, the operation is cancelled.
 *
 *  @param token the token representing a set of callbacks to cancel
 *
 *  @return YES if the operation was stopped because this was the last token to be canceled. NO otherwise.
 */
//不是取消任务的，而是取消任务中的响应，当时当任务中没有响应者的时候，任务也会被取消。
- (BOOL)cancel:(nullable id)token;

@end
