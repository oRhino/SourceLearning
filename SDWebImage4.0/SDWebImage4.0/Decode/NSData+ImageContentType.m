/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Fabrice Aneche
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "NSData+ImageContentType.h"


@implementation NSData (ImageContentType)

//当文件使用二进制流作为传输时，需要制定一套规范，用来区分该文件到底是什么类型的。实际上每个文件的前几个字节都标识着文件的类型，对于一般的图片文件，通过第一个字节(WebP需要12字节)可以辨识出文件类型
/*
1. JPEG (jpg)，文件头：FFD8FFE1
2. PNG (png)，文件头：89504E47
3. GIF (gif)，文件头：47494638
4. TIFF tif;tiff 0x49492A00
5. TIFF tif;tiff 0x4D4D002A
6. RAR Archive (rar)，文件头：52617221
7. WebP : 524946462A73010057454250

*/

+ (SDImageFormat)sd_imageFormatForImageData:(nullable NSData *)data {
    if (!data) {
        return SDImageFormatUndefined;
    }
    
    uint8_t c;
    [data getBytes:&c length:1];
    switch (c) {
        case 0xFF:
            return SDImageFormatJPEG;
        case 0x89:
            return SDImageFormatPNG;
        case 0x47:
            return SDImageFormatGIF;
        case 0x49:
        case 0x4D:
            return SDImageFormatTIFF;
        case 0x52:
            // R as RIFF for WEBP
            if (data.length < 12) {
                return SDImageFormatUndefined;
            }
            
            NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
            if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"]) {
                return SDImageFormatWebP;
            }
    }
    return SDImageFormatUndefined;
}

@end
