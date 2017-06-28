/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloaderOperation.h"
#import "SDWebImageDecoder.h"
#import "UIImage+MultiFormat.h"
#import <ImageIO/ImageIO.h>
#import "SDWebImageManager.h"
#import "NSImage+WebCache.h"

//通知
NSString *const SDWebImageDownloadStartNotification = @"SDWebImageDownloadStartNotification";
NSString *const SDWebImageDownloadReceiveResponseNotification = @"SDWebImageDownloadReceiveResponseNotification";
NSString *const SDWebImageDownloadStopNotification = @"SDWebImageDownloadStopNotification";
NSString *const SDWebImageDownloadFinishNotification = @"SDWebImageDownloadFinishNotification";

//block的键
static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

//回调字典
typedef NSMutableDictionary<NSString *, id> SDCallbacksDictionary;



///NSOperation
//1.默认的NSOperation是同步执行的，当start以后isExecuting会变成YES，然后立即执行main，当main返回后，isExecuting会设为NO并且isFinished会设为YES。当你需要一个异步的Operation，那么重载start方法就可以了。异步的Operation需要重载isExecuting和isFinished，需要手动控制Operation的状态，否则main返回后Operation会直接将isFinished设为YES ->Operation crash。
//2.手动调用start(),默认是在当前线程执行同步操作，应该加入到NSOperationQueue中.如果NSOperationQueue是同步的，那么它会等到NSOperation的isFinished等于YES后，再执行下一个任务，如果是异步的，通过设置maxConcurrentOperationCount来控制同时执行的最大并发数，某个操作完成后，继续其他的操作。
//3.cancel作用是这个操作没执行之前会被取消，正在执行的任务只是将isCancled设置为YES。所以start和main方法中，都必须周期性的对cancelled属性进行判断，如果YES，则立即退出当前，终止操作。start方法中的判断使得尚未开始的操作及时退出,main方法中的判断使得正在执行当中的操作退出。

@interface SDWebImageDownloaderOperation ()

//数组，承载所有的回调Block,通过 'addHandlersForProgress:completed:' 添加数据,数组中存放的是SDCallbacksDictionary类型的数据,即[@{kProgressCallbackKey:block,kCompletedCallbackKey:block},...]
@property (strong, nonatomic, nonnull) NSMutableArray<SDCallbacksDictionary *> *callbackBlocks;


//需要将Operation放入NSOperationQueue里进行的，所以需要重载这两个属性来控制任务的生命周期。
//是否正在执行
@property (assign, nonatomic, getter = isExecuting) BOOL executing;
//是否完成
@property (assign, nonatomic, getter = isFinished) BOOL finished;



//下载的数据
@property (strong, nonatomic, nullable) NSMutableData *imageData;

//初始化时候传进来的参数，这个参数不一定是可用的,不是由当前对象管理,是不安全的。当出现不可用的情况的时候，使用ownedSession
@property (weak, nonatomic, nullable) NSURLSession *unownedSession;

//当unownedSession不能使用时 ,进行初始化
@property (strong, nonatomic, nullable) NSURLSession *ownedSession;

//任务会话
@property (strong, nonatomic, readwrite, nullable) NSURLSessionTask *dataTask;

//队列
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t barrierQueue;

#if SD_UIKIT
//后台任务标识
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;
#endif

@end

@implementation SDWebImageDownloaderOperation {
    //图片:宽 高
    size_t width, height;
#if SD_UIKIT || SD_WATCH
    //图片方向
    UIImageOrientation orientation;
#endif
    //设置是否允许接受缓存中的响应
    BOOL responseFromCached;
}

@synthesize executing = _executing;
@synthesize finished = _finished;

//初始化一个task
//添加响应者
//开启下载任务
//处理下载过程和结束后的事情

- (nonnull instancetype)init {
    return [self initWithRequest:nil inSession:nil options:0];
}

- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options {
    if ((self = [super init])) {
        _request = [request copy];
        _shouldDecompressImages = YES;
        _options = options;
        _callbackBlocks = [NSMutableArray new];
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        _unownedSession = session;
        responseFromCached = YES; // Initially wrong until `- URLSession:dataTask:willCacheResponse:completionHandler: is called or not called
        //并发
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderOperationBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)dealloc {
    SDDispatchQueueRelease(_barrierQueue);
}

//dispatch_barrier_async,这个方法是向数组中添加数据,barrier是栅栏的意思,当一个队列中通过dispatch_barrier_async|sync添加一个任务后,这个任务就起到了一个拦截的作用,之后的任务必须等barrier_async|sync之前添加的任务完成才能够执行,而dispatch_barrier_async与dispatch_barrier_sync的区别也很简单和直观,dispatch_barrier_async不用等这个任务返回,就能够执行队列后的任务,而dispatch_barrier_sync必须等自身返回,才能够执行队列后的任务.往数组中添加数据，对顺序没什么要求,采取dispatch_barrier_async就已经能保证数据添加的安全性了。
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock {
    //新建一个字典对象,进行赋值,添加到数组中
    SDCallbacksDictionary *callbacks = [NSMutableDictionary new];
    if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
    if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
    
     dispatch_barrier_async(self.barrierQueue, ^{
        [self.callbackBlocks addObject:callbacks];
    });
    return callbacks;
}


//根据key取出所有符合key的block，这里采用了同步的方式，相当于加锁
- (nullable NSArray<id> *)callbacksForKey:(NSString *)key {
    __block NSMutableArray<id> *callbacks = nil;
    dispatch_sync(self.barrierQueue, ^{
        // We need to remove [NSNull null] because there might not always be a progress block for each callback
        callbacks = [[self.callbackBlocks valueForKey:key] mutableCopy];
        // removeObjectIdenticalTo:这个方法会移除数组中指定相同地址的元素。移除[NSNull null]
        [callbacks removeObjectIdenticalTo:[NSNull null]];
    });
    return [callbacks copy];    // strip mutability here
}


//取消某一下载操作的回调,dispatch_barrier_sync，保证必须该队列之前的任务都完成，且该取消任务结束后，再将其他的任务加入队列。
- (BOOL)cancel:(nullable id)token {
    __block BOOL shouldCancel = NO;
    dispatch_barrier_sync(self.barrierQueue, ^{
        //删除数组中指定元素,根据对象的地址判断
        [self.callbackBlocks removeObjectIdenticalTo:token];
        if (self.callbackBlocks.count == 0) {
            shouldCancel = YES;
        }
    });
    if (shouldCancel) {
        [self cancel];
    }
    return shouldCancel;
}
//[NSOperationQueue cancelAllOperations]让没运行的NSOperation被取消，正在运行的NSOperation就没办法了。
//[NSOperation cancel]的

//开启下载任务
- (void)start {
    @synchronized (self) {
      // 如果该任务已经被设置为取消了，无需开启下载任务。
        if (self.isCancelled) {
            self.finished = YES;
            //重置
            [self reset];
            return;
        }

#if SD_UIKIT
        //后台处理任务
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
        if (hasApplication && [self shouldContinueWhenAppEntersBackground]) {
            __weak __typeof__ (self) wself = self;
            UIApplication * app = [UIApplicationClass performSelector:@selector(sharedApplication)];
            self.backgroundTaskId = [app beginBackgroundTaskWithExpirationHandler:^{
                __strong __typeof (wself) sself = wself;

                if (sself) {
                    [sself cancel];
                    
                    [app endBackgroundTask:sself.backgroundTaskId];
                    sself.backgroundTaskId = UIBackgroundTaskInvalid;
                }
            }];
        }
#endif
        //如果传入的NSURLSession对象不可用,新建一个NSURLSession对象
        NSURLSession *session = self.unownedSession;
        if (!self.unownedSession) {
            
            //配置
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            sessionConfig.timeoutIntervalForRequest = 15; //超时时间
            
            //delegateQueue传一个nil,那么这个任务会默认在一个串行队列中执行
            self.ownedSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                              delegate:self
                                                         delegateQueue:nil];
            session = self.ownedSession;
        }
       //开启task 并处理回调
        self.dataTask = [session dataTaskWithRequest:self.request];
        self.executing = YES;
    }
    
    [self.dataTask resume];

    if (self.dataTask) {
        //回调进度
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
            progressBlock(0, NSURLResponseUnknownLength, self.request.URL);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            //主线程发送开始下载通知
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:self];
        });
    } else {
        //会话任务创建失败
        [self callCompletionBlocksWithError:[NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Connection can't be initialized"}]];
    }

#if SD_UIKIT
    // 开启后，确保关闭后台任务
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    if (self.backgroundTaskId != UIBackgroundTaskInvalid) {
        UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
        [app endBackgroundTask:self.backgroundTaskId];
        self.backgroundTaskId = UIBackgroundTaskInvalid;
    }
#endif
}


//取消
- (void)cancel {
    @synchronized (self) {
        [self cancelInternal];
    }
}

- (void)cancelInternal {
    if (self.isFinished) return;
    [super cancel];

    if (self.dataTask) {
        [self.dataTask cancel];
        //停止下载 通知
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:self];
        });

        // As we cancelled the connection, its callback won't be called and thus won't
        // maintain the isFinished and isExecuting flags.
        
        //如果正在执行中则表示已经start过，,如果没有结束将isFinished设为yes
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }

    [self reset];
}
//完成
- (void)done {
    self.finished = YES;
    self.executing = NO;
    [self reset];
}
//重置
- (void)reset {
    dispatch_barrier_async(self.barrierQueue, ^{
        [self.callbackBlocks removeAllObjects];
    });
    self.dataTask = nil;
    self.imageData = nil;
    if (self.ownedSession) {
        [self.ownedSession invalidateAndCancel];
        self.ownedSession = nil;
    }
}
//需要实现KVO相关的方法，NSOperationQueue是通过KVO来判断任务状态的
- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}


- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

//告诉我们这个操作相对于调用start方法的线程,是同步还是异步执行。isConcurrent方法默认返回NO,表示操作与调用线程同步执行
//asynchronous 代替
- (BOOL)isConcurrent {
    return YES;
}

#pragma mark NSURLSessionDataDelegate

//HTTP状态码（HTTP Status Code）是一种表示网页服务器响应状态的三位数字编码。通过这些数字，可以简化状态的表达。状态码有几十种，其中首位数字为1-5。根据这5个数字，状态码可以分为5类。1开头的表示请求正在处理；2开头请求已经成功处理；3开头表示重定向；4开头表示请求错误；5开头表示服务器错误。
//常见的有两种200和304。这两个状态码都关系到能否获取重要信息。当客户第一次请求服务器资源，服务器成功返回资源，这时状态码为200。所以，状态码为200的数据包往往包含用户从服务器获取的数据。
//每个资源请求完成后，通常会被缓存在客户端，并会记录资源的有效时间和修改时间。当客户再次请求该资源，客户端首先从缓存中查找该资源。如果该资源存在，并且在有效期，则不请求服务器，就不会产生对应的请求数据包。
//如果不在有效期，客户端会请求服务器，重新获取。服务器会判断修改时间，如果没有修改过，就会返回状态码304，告诉客户端该资源仍然有效，客户端会直接使用缓存的资源。针对304的响应，渗透人员可以分析对应的请求包，获取资源路径。如果该资源不限制访问，就可以直接请求获取。否则，就需要进行Cookie劫持，进行获取。

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    
    //状态码小于 400 但不是304 ,认定为请求成功
    if (![response respondsToSelector:@selector(statusCode)] || (((NSHTTPURLResponse *)response).statusCode < 400 && ((NSHTTPURLResponse *)response).statusCode != 304)) {
        NSInteger expected = response.expectedContentLength > 0 ? (NSInteger)response.expectedContentLength : 0;
        self.expectedSize = expected;
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
            progressBlock(0, expected, self.request.URL);
        }
        
        self.imageData = [[NSMutableData alloc] initWithCapacity:expected];
        self.response = response;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadReceiveResponseNotification object:self];
        });
    }
    else {
        NSUInteger code = ((NSHTTPURLResponse *)response).statusCode;
        
        //This is the case when server returns '304 Not Modified'. It means that remote image is not changed.
        //In case of 304 we need just cancel the operation and return cached image from the cache.
        //304意味着数据没有发生改变
        if (code == 304) {
            [self cancelInternal];
        } else {
            [self.dataTask cancel];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:self];
        });
        
        [self callCompletionBlocksWithError:[NSError errorWithDomain:NSURLErrorDomain code:((NSHTTPURLResponse *)response).statusCode userInfo:nil]];

        [self done];
    }
    
    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

//拼接数据 进行图片的渐进显示
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.imageData appendData:data];

    if ((self.options & SDWebImageDownloaderProgressiveDownload) && self.expectedSize > 0) {
        // The following code is from http://www.cocoaintheshell.com/2011/05/progressive-images-download-imageio/
        // Thanks to the author @Nyx0uf

        // Get the total bytes downloaded
        const NSInteger totalSize = self.imageData.length;

        // Update the data source, we must pass ALL the data, not just the new bytes
        
        //创建一个空的source
        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self.imageData, NULL);

        if (width + height == 0) {
            //获取图片信息 宽 高 方向
            CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
            if (properties) {
                NSInteger orientationValue = -1;
                CFTypeRef val = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
                if (val) CFNumberGetValue(val, kCFNumberLongType, &height);
                val = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
                if (val) CFNumberGetValue(val, kCFNumberLongType, &width);
                val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
                if (val) CFNumberGetValue(val, kCFNumberNSIntegerType, &orientationValue);
                CFRelease(properties);
                
                
#if SD_UIKIT || SD_WATCH
                //使用Core Graphics绘制时,会丢失方向信息导致initWithCGIImage得到的图片方向是不正确的,所以在这里进行记录
                //initWithData 不会
                orientation = [[self class] orientationFromPropertyValue:(orientationValue == -1 ? 1 : orientationValue)];
#endif
            }
        }

        if (width + height > 0 && totalSize < self.expectedSize) {
            // Create the image
            CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);

#if SD_UIKIT || SD_WATCH
            // Workaround for iOS anamorphic image
            //进行图片的绘制
            if (partialImageRef) {
                const size_t partialHeight = CGImageGetHeight(partialImageRef);
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                CGContextRef bmContext = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
                CGColorSpaceRelease(colorSpace);
                if (bmContext) {
                    CGContextDrawImage(bmContext, (CGRect){.origin.x = 0.0f, .origin.y = 0.0f, .size.width = width, .size.height = partialHeight}, partialImageRef);
                    CGImageRelease(partialImageRef);
                    partialImageRef = CGBitmapContextCreateImage(bmContext);
                    CGContextRelease(bmContext);
                }
                else {
                    CGImageRelease(partialImageRef);
                    partialImageRef = nil;
                }
            }
#endif

            if (partialImageRef) {
#if SD_UIKIT || SD_WATCH
                UIImage *image = [UIImage imageWithCGImage:partialImageRef scale:1 orientation:orientation];
#elif SD_MAC
                UIImage *image = [[UIImage alloc] initWithCGImage:partialImageRef size:NSZeroSize];
#endif
                NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
                UIImage *scaledImage = [self scaledImageForKey:key image:image];
                if (self.shouldDecompressImages) {
                    image = [UIImage decodedImageWithImage:scaledImage];
                }
                else {
                    image = scaledImage;
                }
                CGImageRelease(partialImageRef);
                
                [self callCompletionBlocksWithImage:image imageData:nil error:nil finished:NO];
            }
        }

        CFRelease(imageSource);
    }

    for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
        progressBlock(self.imageData.length, self.expectedSize, self.request.URL);
    }
}

//用于响应的缓存设置，如果把回调的参数设置为nil，那么就不会缓存响应，总之，真正缓存的数据就是回调中的参数。
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {

    responseFromCached = NO; // If this method is called, it means the response wasn't read from cache
    NSCachedURLResponse *cachedResponse = proposedResponse;

    if (self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData) {
        // Prevents caching of responses
        cachedResponse = nil;
    }
    if (completionHandler) {
        completionHandler(cachedResponse);
    }
}

#pragma mark NSURLSessionTaskDelegate
//图片下载完成
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @synchronized(self) {
        
        //逻辑处理 发送通知
        self.dataTask = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:self];
            if (!error) {
                [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadFinishNotification object:self];
            }
        });
    }
    
    if (error) {
        //下载失败
        [self callCompletionBlocksWithError:error];
    } else {
        //完成回调block
        if ([self callbacksForKey:kCompletedCallbackKey].count > 0) {
            /**
             *  See #1608 and #1623 - apparently, there is a race condition on `NSURLCache` that causes a crash
             *  Limited the calls to `cachedResponseForRequest:` only for cases where we should ignore the cached response
             *    and images for which responseFromCached is YES (only the ones that cannot be cached).
             *  Note: responseFromCached is set to NO inside `willCacheResponse:`. This method doesn't get called for large images or images behind authentication
             */
            if (self.options & SDWebImageDownloaderIgnoreCachedResponse && responseFromCached && [[NSURLCache sharedURLCache] cachedResponseForRequest:self.request]) {
                // hack
                [self callCompletionBlocksWithImage:nil imageData:nil error:nil finished:YES];
            } else if (self.imageData) {
                //图片处理
                UIImage *image = [UIImage sd_imageWithData:self.imageData];
                NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
                image = [self scaledImageForKey:key image:image];
                
                // Do not force decoding animated GIFs
                if (!image.images) {
                    if (self.shouldDecompressImages) {
                        if (self.options & SDWebImageDownloaderScaleDownLargeImages) {
#if SD_UIKIT || SD_WATCH    //大图进行压缩处理
                            image = [UIImage decodedAndScaledDownImageWithImage:image];
                            [self.imageData setData:UIImagePNGRepresentation(image)];
#endif
                        } else {
                            //解码
                            image = [UIImage decodedImageWithImage:image];
                        }
                    }
                }
                if (CGSizeEqualToSize(image.size, CGSizeZero)) {
                    //图片尺寸为0个像素
                    [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image has 0 pixels"}]];
                } else {
                    //成功
                    [self callCompletionBlocksWithImage:image imageData:self.imageData error:nil finished:YES];
                }
            } else {
                //没有数据
                [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}]];
            }
        }
    }
    [self done];
}


//当我们发出了一个请求，这个请求到达服务器后，假定服务器设置了需要验证。那么这个方法就会被调用。服务器会返回去一个NSURLAuthenticationChallenge。通过NSURLAuthenticationChallenge的protectionSpace,获取授权method。如果这个metho是服务器信任的， 那么我们就可以直接使用服务器返回的证书，当然，我们也可以使用自己的证书，其他情况都会被认为验证失败，当前请求将会被取消。当有了证书后，客户端就可以使用证书中的公钥对数据进行加密了。
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (!(self.options & SDWebImageDownloaderAllowInvalidSSLCertificates)) {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        } else {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            disposition = NSURLSessionAuthChallengeUseCredential;
        }
    } else {
        if (challenge.previousFailureCount == 0) {
            if (self.credential) {
                credential = self.credential;
                disposition = NSURLSessionAuthChallengeUseCredential;
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        }
    }
    
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

#pragma mark Helper methods

//处理图片方向转换
#if SD_UIKIT || SD_WATCH
+ (UIImageOrientation)orientationFromPropertyValue:(NSInteger)value {
    switch (value) {
        case 1:
            return UIImageOrientationUp;
        case 3:
            return UIImageOrientationDown;
        case 8:
            return UIImageOrientationLeft;
        case 6:
            return UIImageOrientationRight;
        case 2:
            return UIImageOrientationUpMirrored;
        case 4:
            return UIImageOrientationDownMirrored;
        case 5:
            return UIImageOrientationLeftMirrored;
        case 7:
            return UIImageOrientationRightMirrored;
        default:
            return UIImageOrientationUp;
    }
}
#endif

//图片裁剪
- (nullable UIImage *)scaledImageForKey:(nullable NSString *)key image:(nullable UIImage *)image {
    return SDScaledImageForKey(key, image);
}

//是否允许后台处理任务
- (BOOL)shouldContinueWhenAppEntersBackground {
    return self.options & SDWebImageDownloaderContinueInBackground;
}


//完成回调
- (void)callCompletionBlocksWithError:(nullable NSError *)error {
    [self callCompletionBlocksWithImage:nil imageData:nil error:error finished:YES];
}

- (void)callCompletionBlocksWithImage:(nullable UIImage *)image
                            imageData:(nullable NSData *)imageData
                                error:(nullable NSError *)error
                             finished:(BOOL)finished {
    NSArray<id> *completionBlocks = [self callbacksForKey:kCompletedCallbackKey];
    dispatch_main_async_safe(^{
        for (SDWebImageDownloaderCompletedBlock completedBlock in completionBlocks) {
            completedBlock(image, imageData, error, finished);
        }
    });
}

@end
