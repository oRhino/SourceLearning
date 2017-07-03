
//
//  SSLViewController.m
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/7/3.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "SSLViewController.h"
#import <Security/Security.h>

@interface SSLViewController ()

@end

@implementation SSLViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self getCertificate];
}

- (void)getCertificate{
    //证书的路径
    NSString *cerPath = [[NSBundle mainBundle] pathForResource:@"baidu" ofType:@"cer"];
    NSData *certData = [NSData dataWithContentsOfFile:cerPath];
    //创建证书对象
    SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    
    //证书->Data
    CFDataRef dataRef = SecCertificateCopyData(certificate);
    //获取证书摘要
    CFStringRef summary = SecCertificateCopySubjectSummary(certificate);
    CFShow(summary);
    
    //policy
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    
    //trust
    SecTrustRef trust = NULL;
    SecTrustCreateWithCertificates(certificate, policy, &trust);
    
    
    //评估
    SecTrustResultType result;
    SecTrustEvaluate(trust, &result);
    
    if (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed) {
        NSLog(@"trust~");
    }
    
    //获取公钥
    SecKeyRef publicKey = SecTrustCopyPublicKey(trust);
    CFShow(publicKey);
    
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
