//
//  ReachabilityViewController.m
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/7/2.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "ReachabilityViewController.h"
#import "AFNetworkReachabilityManager.h"

@interface ReachabilityViewController ()

@property (nonatomic, strong) AFNetworkReachabilityManager *manager
;

@end

@implementation ReachabilityViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(networkChanged:) name:AFNetworkingReachabilityDidChangeNotification object:nil];
}
- (IBAction)start1:(id)sender {
    self.manager = [AFNetworkReachabilityManager sharedManager];
    [self.manager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        switch (status) {
                //未知
            case AFNetworkReachabilityStatusUnknown:
                NSLog(@"你是外星人👽吗?");
                break;
                //网络不可达
            case AFNetworkReachabilityStatusNotReachable:
                NSLog(@"包租婆,断网啦~");
                break;
                //手机网络
            case AFNetworkReachabilityStatusReachableViaWWAN:
                NSLog(@"土豪,我的冰淇淋套餐😆!");
                break;
                //WIFI
            case AFNetworkReachabilityStatusReachableViaWiFi:
                NSLog(@"帅哥,你家WIFI密码是什么!");
                break;
        }
    }];
    [self.manager startMonitoring];
}

- (IBAction)start2:(id)sender {
    self.manager = [AFNetworkReachabilityManager sharedManager];
    [self.manager startMonitoring];
    
}

- (void)networkChanged:(NSNotification *)notification{
    NSString *status = [notification.userInfo objectForKey:AFNetworkingReachabilityNotificationStatusItem];
    NSInteger  statusInt = [status integerValue];
    switch (statusInt) {
            //未知
        case AFNetworkReachabilityStatusUnknown:
            NSLog(@"你是外星人👽吗?");
            break;
            //网络不可达
        case AFNetworkReachabilityStatusNotReachable:
            NSLog(@"包租婆,断网啦~");
            break;
            //手机网络
        case AFNetworkReachabilityStatusReachableViaWWAN:
            NSLog(@"土豪,我的冰淇淋套餐😆!");
            break;
            //WIFI
        case AFNetworkReachabilityStatusReachableViaWiFi:
            NSLog(@"帅哥,你家WIFI密码是什么!");
            break;
    }
}


-(void)dealloc{
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
