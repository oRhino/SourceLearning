/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Laurin Brandner
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIImage+GIF.h"
#import <ImageIO/ImageIO.h>
#import "objc/runtime.h"
#import "NSImage+WebCache.h"

@implementation UIImage (GIF)

+ (UIImage *)sd_animatedGIFWithData:(NSData *)data {
    if (!data) {
        return nil;
    }
    //获取图片源CGImageSourceRef
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    
    //获取图片源数量
    size_t count = CGImageSourceGetCount(source);
    
    UIImage *staticImage;
    
    if (count <= 1) {
        //只有一个图片源,说明不是动画,直接实例化返回
        staticImage = [[UIImage alloc] initWithData:data];
    } else {
        
        //这里仅仅绘制gif的第一帧内容,如果支持GIF播放可以使用FLAnimatedImageView这个类别
#if SD_WATCH
        CGFloat scale = 1;
        scale = [WKInterfaceDevice currentDevice].screenScale;
#elif SD_UIKIT
        CGFloat scale = 1;
        scale = [UIScreen mainScreen].scale;
#endif
        
        //获取第一帧的CGImage
        CGImageRef CGImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
#if SD_UIKIT || SD_WATCH
        //绘制
        UIImage *frameImage = [UIImage imageWithCGImage:CGImage scale:scale orientation:UIImageOrientationUp];
        staticImage = [UIImage animatedImageWithImages:@[frameImage] duration:0.0f];
#elif SD_MAC
        staticImage = [[UIImage alloc] initWithCGImage:CGImage size:NSZeroSize];
#endif
        CGImageRelease(CGImage);
    }
    //释放资源
    CFRelease(source);
    
    return staticImage;
}

- (BOOL)isGIF {
    return (self.images != nil);
}

@end
