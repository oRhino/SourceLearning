/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

@implementation SDWebImageDownloadToken
@end


@interface SDWebImageDownloader () <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

//下载队列(包含operationClass对象)
@property (strong, nonatomic, nonnull) NSOperationQueue *downloadQueue;
//最后添加的操作(用于更改操作执行顺序时(LIFO)进行记录操作对象)
@property (weak, nonatomic, nullable) NSOperation *lastAddedOperation;
//自定义的下载操作类(继承NSOperation,遵循SDWebImageDownloaderOperationInterface协议,这里使用SDWebImageDownloaderOperation)
@property (assign, nonatomic, nullable) Class operationClass;
//下载操作字典(图片URL:操作对象)
@property (strong, nonatomic, nonnull) NSMutableDictionary<NSURL *, SDWebImageDownloaderOperation *> *URLOperations;
//请求头信息
@property (strong, nonatomic, nullable) SDHTTPHeadersMutableDictionary *HTTPHeaders;

//这个队列只用于连续的处理下载操作的网络响应(操作对象的创建和取消)
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t barrierQueue;

//网络请求,在DataTask中运行
@property (strong, nonatomic) NSURLSession *session;

@end

@implementation SDWebImageDownloader

+ (void)initialize {
    
    //使用SDNetworkActivityIndicator网络指示器,可自行下载(http://github.com/rs/SDNetworkActivityIndicator)进行导入(#import "SDNetworkActivityIndicator.h")
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {
        
        //忽略警告信息
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop
        
        //添加监听时先移除,因为这个方法可能执行多次
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}
//单例对象
+ (nonnull instancetype)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

//构造函数
- (nonnull instancetype)init {
    return [self initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
}

//最终的构造方法
//sessionConfiguration 网络会话配置,一般使用默认
- (nonnull instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)sessionConfiguration {
    if ((self = [super init])) {
        //相关初始化
        //自定义下载操作类 SDWebImageDownloaderOperation
        _operationClass = [SDWebImageDownloaderOperation class];
        //允许图片压缩
        _shouldDecompressImages = YES;
        //先进先出
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder;
        _downloadQueue = [NSOperationQueue new];
        //最大并发数量 6
        _downloadQueue.maxConcurrentOperationCount = 6;
        _downloadQueue.name = @"com.hackemist.SDWebImageDownloader";
        _URLOperations = [NSMutableDictionary new];
        
        
        //请求头设置
#ifdef SD_WEBP
        //webp格式 q=0.8是权重系数,取值范围0-1,表示优先接受image/webp,其次接受image/*的图片
        _HTTPHeaders = [@{@"Accept": @"image/webp,image/*;q=0.8"} mutableCopy];
#else
        _HTTPHeaders = [@{@"Accept": @"image/*;q=0.8"} mutableCopy];
#endif
        //并发队列
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        //下载超时时间
        _downloadTimeout = 15.0;
        sessionConfiguration.timeoutIntervalForRequest = _downloadTimeout;
        
        //这里delegateQueue传nil,这个会话将会创建一个串行操作队列
        self.session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                     delegate:self
                                                delegateQueue:nil];
    }
    return self;
}

- (void)dealloc {
    //不再需要一个会话调用使其失效(取消未完成任务)
    [self.session invalidateAndCancel];
    self.session = nil;

    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
}


#pragma mark - setter/getter
//设置请求头
- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(nullable NSString *)field {
    if (value) {
        //有值,设置
        self.HTTPHeaders[field] = value;
    }else {
        // nil 删除
        [self.HTTPHeaders removeObjectForKey:field];
    }
}
//请求头
- (nullable NSString *)valueForHTTPHeaderField:(nullable NSString *)field {
    return self.HTTPHeaders[field];
}
//设置最大并发量
- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}
//当前下载操作对象数量
- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}
//最大并发量
- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}

//必须是NSOperation的子类,且遵循SDWebImageDownloaderOperationInterface协议
- (void)setOperationClass:(nullable Class)operationClass {
    if (operationClass && [operationClass isSubclassOfClass:[NSOperation class]] && [operationClass conformsToProtocol:@protocol(SDWebImageDownloaderOperationInterface)]) {
        _operationClass = operationClass;
    } else {
        _operationClass = [SDWebImageDownloaderOperation class];
    }
}


//下载操作 主要方法
//返回一个SDWebImageDownloadToken对象,可以用来取消下载任务
- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock {
    __weak SDWebImageDownloader *wself = self;

    return [self addProgressCallback:progressBlock completedBlock:completedBlock forURL:url createCallback:^SDWebImageDownloaderOperation *{
        
        //创建操作对象完成之后 进行网络参数配置和处理操作列表的执行顺序(添加依赖)
        
        
        __strong __typeof (wself) sself = wself;
        //超时时间
        NSTimeInterval timeoutInterval = sself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }
        //为了防止潜在的重复进行缓存(NSURLCache + SDImageCache),禁用了image requests
        //SDWebImageDownloaderUseNSURLCache -> NSURLRequestUseProtocolCachePolicy
        
        // cachePolicy:创建的request所使用的缓存策略，默认使用`NSURLRequestUseProtocolCachePolicy`，该策略表示如果缓存不存在，直接从服务端获取。如果缓存存在，会根据response中的Cache-Control字段判断,下一步操作，如: Cache-Control字段为must-revalidata, 则 询问服务端该数据是否有更新，无更新话直接返回给用户缓存数据，若已更新，则请求服务端.
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        
        //HTTPShouldHandleCookies表示是否应该给request设置cookie并随request一起发送出去,如果设置HTTPShouldHandleCookies为YES，就处理存储在NSHTTPCookieStore中的cookies
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        
        // HTTPShouldUsePipelining表示receiver(client客户端)的下一个信息是否必须等到上一个请求回复才能发送。如果为YES表示可以，NO表示必须等receiver收到先前的回复才能发送下个信息。
        request.HTTPShouldUsePipelining = YES;
        
        //请求头
        if (sself.headersFilter) {
            //将block做为参数,对请求头信息进行过滤或操作
            request.allHTTPHeaderFields = sself.headersFilter(url, [sself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = sself.HTTPHeaders;
        }
        
        //根据操作配置,请求参数,网络会话创建下载操作对象
        SDWebImageDownloaderOperation *operation = [[sself.operationClass alloc] initWithRequest:request inSession:sself.session options:options];
        //是否允许压缩
        operation.shouldDecompressImages = sself.shouldDecompressImages;
        
        //认证
        if (sself.urlCredential) {
            operation.credential = sself.urlCredential;
        } else if (sself.username && sself.password) {
            //新建认证对象
            operation.credential = [NSURLCredential credentialWithUser:sself.username password:sself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        //操作对象优先级
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }
        //添加到操作队列
        [sself.downloadQueue addOperation:operation];
        if (sself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            
            //如果是后进先出,为上一个添加的操作对象添加依赖为当前的操作对象,然后重新赋值
            [sself.lastAddedOperation addDependency:operation];
            sself.lastAddedOperation = operation;
        }

        return operation;
    }];
}

//取消 通过关联的下载令牌信息(SDWebImageDownloadToken)
- (void)cancel:(nullable SDWebImageDownloadToken *)token {
    dispatch_barrier_async(self.barrierQueue, ^{
        SDWebImageDownloaderOperation *operation = self.URLOperations[token.url];
        BOOL canceled = [operation cancel:token.downloadOperationCancelToken];
        if (canceled) {
            [self.URLOperations removeObjectForKey:token.url];
        }
    });
}
//main
- (nullable SDWebImageDownloadToken *)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock
                                           completedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock
                                                   forURL:(nullable NSURL *)url
                                           createCallback:(SDWebImageDownloaderOperation *(^)())createCallback {
    
    //URL作为回调词典的键,所以不能为空,为空时,直接回调这个block,没有图片或数据返回
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return nil;
    }

    __block SDWebImageDownloadToken *token = nil;

    dispatch_barrier_sync(self.barrierQueue, ^{
        //在当前操作字典中获取,不存在时,创建一个操作对象进行赋值,
        SDWebImageDownloaderOperation *operation = self.URLOperations[url];
        if (!operation) {
            
            //执行创建操作对象的block
            operation = createCallback();
            self.URLOperations[url] = operation;

            __weak SDWebImageDownloaderOperation *woperation = operation;
            //完成时,在操作字典中清除这个操作对象
            operation.completionBlock = ^{
              SDWebImageDownloaderOperation *soperation = woperation;
              if (!soperation) return;
              if (self.URLOperations[url] == soperation) {
                  [self.URLOperations removeObjectForKey:url];
              };
            };
        }
        //关联(SDWebImageDownloadToken)的信息 url为图片下载地址,downloadOperationCancelToken为一个可变字典包含(下载进度回调的block和完成下载的回调block)
        id downloadOperationCancelToken = [operation addHandlersForProgress:progressBlock completed:completedBlock];

        token = [SDWebImageDownloadToken new];
        token.url = url;
        token.downloadOperationCancelToken = downloadOperationCancelToken;
    });

    return token;
}
//挂起
- (void)setSuspended:(BOOL)suspended {
    (self.downloadQueue).suspended = suspended;
}
//取消所有操作
- (void)cancelAllDownloads {
    [self.downloadQueue cancelAllOperations];
}

#pragma mark Helper methods
//在操作队列中遍历查找指定的下载任务
- (SDWebImageDownloaderOperation *)operationWithTask:(NSURLSessionTask *)task {
    SDWebImageDownloaderOperation *returnOperation = nil;
    for (SDWebImageDownloaderOperation *operation in self.downloadQueue.operations) {
        //操作标识
        if (operation.dataTask.taskIdentifier == task.taskIdentifier) {
            returnOperation = operation;
            break;
        }
    }
    return returnOperation;
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didCompleteWithError:error];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    
    completionHandler(request);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
}



@end
