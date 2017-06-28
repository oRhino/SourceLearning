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


//添加一个只读缓存路径,用于给app预装一些图片
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


//异步查询缓存,成功后进行回调.该方法返回一个操作对象,可用于管理(取消)
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key done:(nullable SDCacheQueryCompletedBlock)doneBlock;


// 同步返回内存中指定的图片缓存
- (nullable UIImage *)imageFromMemoryCacheForKey:(nullable NSString *)key;


//同步 获取磁盘中指定的图片
- (nullable UIImage *)imageFromDiskCacheForKey:(nullable NSString *)key;


//获取缓存(memory and or disk) 同步
- (nullable UIImage *)imageFromCacheForKey:(nullable NSString *)key;

#pragma mark - Remove Ops

//异步 同事删除内存,磁盘中指定的缓存
- (void)removeImageForKey:(nullable NSString *)key withCompletion:(nullable SDWebImageNoParamsBlock)completion;

//异步 删除磁盘中指定的缓存文件
- (void)removeImageForKey:(nullable NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(nullable SDWebImageNoParamsBlock)completion;

#pragma mark - Cache clean Ops

// 清除内存中的缓存
- (void)clearMemory;

//异步删除所有的磁盘文件 删除完成后执行回调
- (void)clearDiskOnCompletion:(nullable SDWebImageNoParamsBlock)completion;


//异步删除过期的磁盘文件 删除完成后执行回调
- (void)deleteOldFilesWithCompletionBlock:(nullable SDWebImageNoParamsBlock)completionBlock;

#pragma mark - Cache Info

// 磁盘缓存大小 同步
- (NSUInteger)getSize;


// 磁盘缓存图片数量
- (NSUInteger)getDiskCount;


// 异步计算磁盘缓存的大小 回调
- (void)calculateSizeWithCompletionBlock:(nullable SDWebImageCalculateSizeBlock)completionBlock;

#pragma mark - Cache Paths

//缓存路径
- (nullable NSString *)cachePathForKey:(nullable NSString *)key inPath:(nonnull NSString *)path;

//指定的URL的默认缓存路径
- (nullable NSString *)defaultCachePathForKey:(nullable NSString *)key;

@end
