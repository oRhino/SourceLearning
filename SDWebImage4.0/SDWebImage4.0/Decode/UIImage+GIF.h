/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Laurin Brandner
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"

@interface UIImage (GIF)

//当图片源有多个(gif格式)的时候,通过CGImageSourceRef获取图片的第一帧返回,这里主要涉及<Image I/0>框架的内容

+ (UIImage *)sd_animatedGIFWithData:(NSData *)data;

/**
 *  Checks if an UIImage instance is a GIF. Will use the `images` array
 */
- (BOOL)isGIF;

@end
