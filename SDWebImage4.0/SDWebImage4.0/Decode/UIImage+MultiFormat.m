/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIImage+MultiFormat.h"
#import "UIImage+GIF.h"
#import "NSData+ImageContentType.h"
#import <ImageIO/ImageIO.h>

#ifdef SD_WEBP
#import "UIImage+WebP.h"
#endif

@implementation UIImage (MultiFormat)

+ (nullable UIImage *)sd_imageWithData:(nullable NSData *)data {
    if (!data) {
        return nil;
    }
    
    UIImage *image;
    //格式判断
    SDImageFormat imageFormat = [NSData sd_imageFormatForImageData:data];
    if (imageFormat == SDImageFormatGIF) {
        //gif 返回第一帧图像
        image = [UIImage sd_animatedGIFWithData:data];
    }
#ifdef SD_WEBP
    else if (imageFormat == SDImageFormatWebP)
    {
        //webp
        image = [UIImage sd_imageWithWebPData:data];
    }
#endif
    else {
        image = [[UIImage alloc] initWithData:data];
#if SD_UIKIT || SD_WATCH
        //获取方向信息
        UIImageOrientation orientation = [self sd_imageOrientationFromImageData:data];
        if (orientation != UIImageOrientationUp) {
              //实例化  UIImageOrientationUp为默认,直接返回即可
            image = [UIImage imageWithCGImage:image.CGImage
                                        scale:image.scale
                                  orientation:orientation];
        }
#endif
    }


    return image;
}

#if SD_UIKIT || SD_WATCH
//获取图片的方向
+(UIImageOrientation)sd_imageOrientationFromImageData:(nonnull NSData *)imageData {
    UIImageOrientation result = UIImageOrientationUp;
    //获取图片源数据
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (imageSource) {
        //首帧图片的属性
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
        if (properties) {
            CFTypeRef val;
            int exifOrientation;
             //获取属性字典中的方向信息
            val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
            if (val) {
                //转换
                CFNumberGetValue(val, kCFNumberIntType, &exifOrientation);
                result = [self sd_exifOrientationToiOSOrientation:exifOrientation];
            } // else - if it's not set it remains at up
            CFRelease((CFTypeRef) properties);
        } else {
            //NSLog(@"NO PROPERTIES, FAIL");
        }
        CFRelease(imageSource);
    }
    return result;
}

#pragma mark EXIF orientation tag converter
// Convert an EXIF image orientation to an iOS one.
// reference see here: http://sylvana.net/jpegcrop/exif_orientation.html

//图片方向转换 int -> 枚举类型
+ (UIImageOrientation) sd_exifOrientationToiOSOrientation:(int)exifOrientation {
    UIImageOrientation orientation = UIImageOrientationUp;
    switch (exifOrientation) {
        case 1:
            orientation = UIImageOrientationUp;
            break;

        case 3:
            orientation = UIImageOrientationDown;
            break;

        case 8:
            orientation = UIImageOrientationLeft;
            break;

        case 6:
            orientation = UIImageOrientationRight;
            break;

        case 2:
            orientation = UIImageOrientationUpMirrored;
            break;

        case 4:
            orientation = UIImageOrientationDownMirrored;
            break;

        case 5:
            orientation = UIImageOrientationLeftMirrored;
            break;

        case 7:
            orientation = UIImageOrientationRightMirrored;
            break;
        default:
            break;
    }
    return orientation;
}
#endif

- (nullable NSData *)sd_imageData {
    return [self sd_imageDataAsFormat:SDImageFormatUndefined];
}
/*
CGImageAlphaInfo是一个枚举,表示alpha分量的位置及颜色分量是否做预处理：

- kCGImageAlphaLast：alpha分量存储在每个像素中最不显著的位置，如RGBA。
- kCGImageAlphaFirst：alpha分量存储在每个像素中最显著的位置，如ARGB。
- kCGImageAlphaPremultipliedLast：alpha分量存储在每个像素中最不显著的位置，但颜色分量已经乘以了alpha值。
- kCGImageAlphaPremultipliedFirst：alpha分量存储在每个像素中最显著的位置，同时颜色分量已经乘以了alpha值。
- kCGImageAlphaNoneSkipLast：没有alpha分量。如果像素的总大小大于颜色空间中颜色分量数目所需要的空间，则最不显著位置的位将被忽略。
- kCGImageAlphaNoneSkipFirst：没有alpha分量。如果像素的总大小大于颜色空间中颜色分量数目所需要的空间，则最显著位置的位将被忽略。
- kCGImageAlphaNone：等于kCGImageAlphaNoneSkipLast。
 
 */

//将UIImage对象转换成二进制,有透明通道的返回PNG,否则返回JPEG
- (nullable NSData *)sd_imageDataAsFormat:(SDImageFormat)imageFormat {
    NSData *imageData = nil;
    if (self) {
#if SD_UIKIT || SD_WATCH
        int alphaInfo = CGImageGetAlphaInfo(self.CGImage);
        //透明通道
        BOOL hasAlpha = !(alphaInfo == kCGImageAlphaNone ||
                          alphaInfo == kCGImageAlphaNoneSkipFirst ||
                          alphaInfo == kCGImageAlphaNoneSkipLast);
        
        BOOL usePNG = hasAlpha;
        
        // the imageFormat param has priority here. But if the format is undefined, we relly on the alpha channel
        if (imageFormat != SDImageFormatUndefined) {
            usePNG = (imageFormat == SDImageFormatPNG);
        }
        
        if (usePNG) {
            imageData = UIImagePNGRepresentation(self);
        } else {
            imageData = UIImageJPEGRepresentation(self, (CGFloat)1.0);
        }
#else
        NSBitmapImageFileType imageFileType = NSJPEGFileType;
        if (imageFormat == SDImageFormatGIF) {
            imageFileType = NSGIFFileType;
        } else if (imageFormat == SDImageFormatPNG) {
            imageFileType = NSPNGFileType;
        }
        
        imageData = [NSBitmapImageRep representationOfImageRepsInArray:self.representations
                                                             usingType:imageFileType
                                                            properties:@{}];
#endif
    }
    return imageData;
}


@end
