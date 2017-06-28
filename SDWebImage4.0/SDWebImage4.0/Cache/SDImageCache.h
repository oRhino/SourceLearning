/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

@class SDImageCacheConfig;

typedef NS_ENUM(NSInteger, SDImageCacheType) {
    //没有缓存
    SDImageCacheTypeNone,
    //磁盘缓存
    SDImageCacheTypeDisk,
    //Memory
    SDImageCacheTypeMemory
};

//查询队列完成回调block
typedef void(^SDCacheQueryCompletedBlock)(UIImage * _Nullable image, NSData * _Nullable data, SDImageCacheType cacheType);
//检查缓存回调
typedef void(^SDWebImageCheckCacheCompletionBlock)(BOOL isInCache);
//计算缓存大小回调
typedef void(^SDWebImageCalculateSizeBlock)(NSUInteger fileCount, NSUInteger totalSize);


//SDImageCache主要是Memory缓存,但是同样可以选择磁盘进行缓存.磁盘进行缓存是异步的,不会阻塞主线程
@interface SDImageCache : NSObject

#pragma mark - Properties

//所有的缓存配置信息
@property (nonatomic, nonnull, readonly) SDImageCacheConfig *config;

// 设置内存的最大缓存是多少，这个是以像素为单位的
@property (assign, nonatomic) NSUInteger maxMemoryCost;

//设置内存的最大缓存数量是多少
@property (assign, nonatomic) NSUInteger maxMemoryCountLimit;

#pragma mark - Singleton and initialization


// 单例对象
+ (nonnull instancetype)sharedImageCache;

//命名空间
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns;

//默认构造方法
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns
                       diskCacheDirectory:(nonnull NSString *)directory NS_DESIGNATED_INITIALIZER;

#pragma mark - Cache paths

- (nullable NSString *)makeDiskCachePath:(nonnull NSString*)fullNamespace;

/**
 * Add a read-only cache path to search for images pre-cached by SDImageCache
 * Useful if you want to bundle pre-loaded images with your app
 *
 * @param path The path to use for this read-only cache path
 */
- (void)addReadOnlyCachePath:(nonnull NSString *)path;

#pragma mark - Store Ops

// 根据指定的字符串,异步缓存图片到Memory和磁盘中
- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

// 根据指定的字符串,异步缓存图片到内存中和是否缓存到磁盘中(toDisk)
- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

//最终方法 主要
- (void)storeImage:(nullable UIImage *)image
         imageData:(nullable NSData *)imageData
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

//异步缓存到磁盘中
- (void)storeImageDataToDisk:(nullable NSData *)imageData forKey:(nullable NSString *)key;

#pragma mark - Query and Retrieve Ops

// 异步检查图片是否已经缓存在磁盘中,回调block将在主队列中执行
- (void)diskImageExistsWithKey:(nullable NSString *)key completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;

/**
 * Operation that queries the cache asynchronously and call the completion when done.
 *
 * @param key       The unique key used to store the wanted image
 * @param doneBlock The completion block. Will not get called if the operation is cancelled
 *
 * @return a NSOperation instance containing the cache op
 */
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key done:(nullable SDCacheQueryCompletedBlock)doneBlock;

/**
 * Query the memory cache synchronously.
 *
 * @param key The unique key used to store the image
 返回内存中指定的图片缓存
 */
- (nullable UIImage *)imageFromMemoryCacheForKey:(nullable NSString *)key;

/**
 * Query the disk cache synchronously.
 *
 * @param key The unique key used to store the image
  返回磁盘中指定的图片缓存
 */
- (nullable UIImage *)imageFromDiskCacheForKey:(nullable NSString *)key;

/**
 * Query the cache (memory and or disk) synchronously after checking the memory cache.
 *
 * @param key The unique key used to store the image
 */
- (nullable UIImage *)imageFromCacheForKey:(nullable NSString *)key;

#pragma mark - Remove Ops

/**
 * Remove the image from memory and disk cache asynchronously
 *
 * @param key             The unique image cache key
 * @param completion      A block that should be executed after the image has been removed (optional)
 */
- (void)removeImageForKey:(nullable NSString *)key withCompletion:(nullable SDWebImageNoParamsBlock)completion;

/**
 * Remove the image from memory and optionally disk cache asynchronously
 *
 * @param key             The unique image cache key
 * @param fromDisk        Also remove cache entry from disk if YES
 * @param completion      A block that should be executed after the image has been removed (optional)
 */
- (void)removeImageForKey:(nullable NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(nullable SDWebImageNoParamsBlock)completion;

#pragma mark - Cache clean Ops

/**
 * Clear all memory cached images
 清除缓存
 */
- (void)clearMemory;

/**
 * Async clear all disk cached images. Non-blocking method - returns immediately.
 * @param completion    A block that should be executed after cache expiration completes (optional)
 */
- (void)clearDiskOnCompletion:(nullable SDWebImageNoParamsBlock)completion;

/**
 * Async remove all expired cached image from disk. Non-blocking method - returns immediately.
 * @param completionBlock A block that should be executed after cache expiration completes (optional)
 
 */
- (void)deleteOldFilesWithCompletionBlock:(nullable SDWebImageNoParamsBlock)completionBlock;

#pragma mark - Cache Info

/**
 * Get the size used by the disk cache
 磁盘缓存大小
 */
- (NSUInteger)getSize;

/**
 * Get the number of images in the disk cache
 磁盘缓存图片数量
 */
- (NSUInteger)getDiskCount;

/**
 * Asynchronously calculate the disk cache's size.
 异步计算磁盘缓存的大小
 */
- (void)calculateSizeWithCompletionBlock:(nullable SDWebImageCalculateSizeBlock)completionBlock;

#pragma mark - Cache Paths

/**
 *  Get the cache path for a certain key (needs the cache path root folder)
 *
 *  @param key  the key (can be obtained from url using cacheKeyForURL)
 *  @param path the cache path root folder
 *
 *  @return the cache path
 */
- (nullable NSString *)cachePathForKey:(nullable NSString *)key inPath:(nonnull NSString *)path;

/**
 *  Get the default cache path for a certain key
 *
 *  @param key the key (can be obtained from url using cacheKeyForURL)
 *
 *  @return the default cache path
 */
- (nullable NSString *)defaultCachePathForKey:(nullable NSString *)key;

@end
