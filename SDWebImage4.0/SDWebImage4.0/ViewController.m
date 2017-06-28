//
//  ViewController.m
//  SDWebImage4.0
//
//  Created by Rhino on 2017/6/26.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "ViewController.h"
#import "UIImageView+WebCache.h"
#import "UIImageView+HighlightedWebCache.h"
#import "UIView+WebCache.h"


#define GIFURL @"http://www.gif5.net/img/images/2015/10/19/NW9pUjZLYUI1b21UNVkyQjVMaXE1NFdPNmFXOA==.gif"
#define LARGEURL @"https://cdn.eso.org/images/large/eso0934a.jpg"
@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@end

@implementation ViewController


typedef enum{
    a = 1 << 0,
    b = 1 << 1,
    c = 1 << 2,
    d = 1 << 3
}testEnum;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //测试Gif
//    [self.imageView sd_setImageWithURL:[NSURL URLWithString:GIFURL]
//                      placeholderImage:[UIImage imageNamed:@""] completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
//        NSLog(@"%ld",image.images.count);
//    }];
    
    //测试渐进式加载
    [self.imageView sd_setShowActivityIndicatorView:YES];
//    [self.imageView sd_setImageWithURL:[NSURL URLWithString:LARGEURL] placeholderImage:nil options:SDWebImageProgressiveDownload];
    
    [self.imageView sd_setImageWithURL:[NSURL URLWithString:LARGEURL]];
    
//    NSLog(@"%d", 1<<2);//2^2 左移
//    NSLog(@"%d",2>>1); //010 -> 001 1
    
    
//    [self.imageView setHighlightedImage:[UIImage imageNamed:@"SDWebImageClassDiagram"]];
//    [self.imageView setHighlighted:YES];
    
    
    testEnum e = a | b; //3
    /*
     0000 0001   0000 0011   0000 0011     0000 0011
     0000 0010   0000 0001   0000 0010     0000 0100
 |   0000 0011 & 0000 0001   0000 0010     0000 0000
     */
    if (e & a) {
        printf("满足条件a");
        //满足a要做的事
    }
    if (e & b) {
        printf("满足条件b");
        //满足b要做的事
    }
    if (e & c) {
        printf("满足条件c");
        //满足c要做的事
    }
}

- (void)saxBox{
    
    NSHomeDirectory();
    
    NSArray <NSString *>*pathArray = NSSearchPathForDirectoriesInDomains(NSPreferencePanesDirectory, NSUserDomainMask, YES);
    NSLog(@"cache:%@",pathArray);
    [[NSUserDefaults standardUserDefaults]setObject:pathArray forKey:@"1"];
        
    NSString *temp = NSTemporaryDirectory();
    NSLog(@"temp:%@",temp);
     [[NSUserDefaults standardUserDefaults]setObject:temp forKey:@"2"];
    
    NSArray <NSString *>*pathArray2 = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSLog(@"document:%@",pathArray2);
     [[NSUserDefaults standardUserDefaults]setObject:pathArray2 forKey:@"3"];
    
    NSArray <NSString *>*pathArray3 = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSLog(@"libary:%@",pathArray3);
     [[NSUserDefaults standardUserDefaults]setObject:pathArray3 forKey:@"4"];
        
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
