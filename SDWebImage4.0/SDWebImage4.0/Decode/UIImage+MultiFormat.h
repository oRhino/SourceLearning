/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "NSData+ImageContentType.h"

@interface UIImage (MultiFormat)

//UIImage <->NSData的相互转换:UIImage+MultiFormat

+ (nullable UIImage *)sd_imageWithData:(nullable NSData *)data;
- (nullable NSData *)sd_imageData;
//将UIImage对象转换成二进制,有透明通道的返回PNG,否则返回JPEG
- (nullable NSData *)sd_imageDataAsFormat:(SDImageFormat)imageFormat;

@end
