//
//  SessionViewController.m
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/6/29.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "SessionViewController.h"
//NSURLsessionTask 是一个抽象类，其下有 3 个实体子类可以直接使用：NSURLSessionDataTask、NSURLSessionUploadTask、NSURLSessionDownloadTask。这 3 个子类封装了现代程序三个最基本的网络任务：获取数据，比如 JSON 或者 XML，上传文件和下载文件。
//当一个 NSURLSessionDataTask 完成时，它会带有相关联的数据，而一个 NSURLSessionDownloadTask 任务结束时，它会带回已下载文件的一个临时的文件路径（还记得前面的location吧）。因为一般来说，服务端对于一个上传任务的响应也会有相关数据返回，所以NSURLSessionUploadTask 继承自 NSURLSessionDataTask。

@interface SessionViewController ()

@end

@implementation SessionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
//    NSURLSessionTask
//    NSURLSessionDataTask
//    NSURLSessionDownloadTask
//    NSURLSessionUploadTask
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
