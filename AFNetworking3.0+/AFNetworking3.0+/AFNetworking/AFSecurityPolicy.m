// AFSecurityPolicy.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFSecurityPolicy.h"

#import <AssertMacros.h>

#if !TARGET_OS_IOS && !TARGET_OS_WATCH && !TARGET_OS_TV
//把key到出为NSData
static NSData * AFSecKeyGetData(SecKeyRef key) {
    CFDataRef data = NULL;

    __Require_noErr_Quiet(SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data), _out);

    return (__bridge_transfer NSData *)data;

_out:
    if (data) {
        CFRelease(data);
    }

    return nil;
}
#endif

//比较两个key是否相等，如果是iOS/watch/tv直接使用isEqual方法就可进行比较。因为SecKeyRef本质上是一个struct，是不能直接用isEqual比较的，正好使用上边的那个方法把它转为NSData就可以了。
static BOOL AFSecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2) {
#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_TV
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
#else
    return [AFSecKeyGetData(key1) isEqual:AFSecKeyGetData(key2)];
#endif
}


//当条件返回false时，执行标记以后的代码
/*
#ifndef __Require_Quiet
#define __Require_Quiet(assertion, exceptionLabel)                            \
do                                                                          \
{                                                                           \
if ( __builtin_expect(!(assertion), 0) )                                \
{                                                                       \
goto exceptionLabel;                                                \
}                                                                       \
} while ( 0 )
#endif
*/

//当条件抛出异常时，执行标记以后的代码
/*
 #ifndef __Require_noErr_Quiet
 #define __Require_noErr_Quiet(errorCode, exceptionLabel)                      \
 do                                                                          \
 {                                                                           \
 if ( __builtin_expect(0 != (errorCode), 0) )                            \
 {                                                                       \
 goto exceptionLabel;                                                \
 }                                                                       \
 } while ( 0 )
 #endif
 */
//在证书中获取公钥

// 此函数没什么特别要提及的，和AFPublicKeyTrustChainForServerTrust实现的原理基本一致
// 区别仅仅在该函数是返回单个证书的公钥（所以传入的参数是一个证书），而AFPublicKeyTrustChainForServerTrust返回的是serverTrust的证书链中所有证书公钥
static id AFPublicKeyForCertificate(NSData *certificate) {
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;
    
    //1.根据二进制的certificate生成SecCertificateRef类型的证书,NSData *certificate 通过CoreFoundation (__bridge CFDataRef)转换成 CFDataRef
     // 因为此处传入的certificate参数是NSData类型的，所以需要使用SecCertificateCreateWithData来将NSData对象转化为SecCertificateRef对象

    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
    
    //2.如果allowedCertificate为空，则执行标记_out后边的代码
    __Require_Quiet(allowedCertificate != NULL, _out);
    
    //3.新建policy为X.509
    policy = SecPolicyCreateBasicX509();
    
    //4.创建SecTrustRef对象，如果出错就跳到_out标记处
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust), _out);
    //5.校验证书的过程，这个不是异步的。
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);
    
    //6.在SecTrustRef对象中取出公钥
    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);

_out:
    
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }

    if (policy) {
        CFRelease(policy);
    }

    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }

    return allowedPublicKey;
}

/*
// Require_noErr_Quiet是一个宏定义函数，表示如果errorCode不为0（0表示没有错误），那么就使用C语言中的go语句，跳到对应exceptionLabel地方开始执行代码。
#ifndef __Require_noErr_Quiet
#define __Require_noErr_Quiet(errorCode, exceptionLabel)                      \
do                                                                          \
{                                                                           \
if ( __builtin_expect(0 != (errorCode), 0) )                            \
{                                                                       \
goto exceptionLabel;                                                \
}                                                                       \
} while ( 0 )
#endif
*/
//返回服务器是否是可以信任的

static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    BOOL isValid = NO;
    SecTrustResultType result;
    //把结果赋值给result
    // 对照下面的Require_noErr_Quiet函数解释，此处errorCode指的就是SecTrustEvaluate(serverTrust, &result)函数的返回值。如果serverTrust评估出错，那么就直接执行return isValid，默认isValid为NO。
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);
    
    //kSecTrustResultUnspecified 不是自己设置的证书通过
    //kSecTrustResultProceed 用户自己生成证书通过
    
    // 如果SecTrustEvaluate函数评估没出错，那么就看result的结果
    // 只有当result为kSecTrustResultUnspecified（此标志表示serverTrust评估成功，此证书也被暗中信任了，但是用户并没有显示地决定信任该证书），或者当result为kSecTrustResultProceed（此标志表示评估成功，和上面不同的是该评估得到了用户认可），这两者取其一就可以认为对serverTrust评估成功
    // 在下面有对result类型（SecTrustResultType）的简单讲解
    // kSecTrustResultUnspecified和kSecTrustResultProceed都是SecTrustResultType类型
    /**
     SecTrustResultType中枚举值的含义包括两个方面：一个是指评估是否成功，另一个是指该评估结果是不是由用户决定的。对于是不是由用户决定的这个问题，上面kSecTrustResultUnspecified和kSecTrustResultProceed就是一个很好的例子
     */
    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);

_out:
    return isValid;
}
//取出服务器返回的所有证书,
// 获取到serverTrust中证书链上的所有证书
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    // 使用SecTrustGetCertificateCount函数t获取到serverTrust中需要评估的证书链中的证书数目，并保存到certificateCount中
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
// 使用SecTrustGetCertificateAtIndex函数获取到证书链中的每个证书，并添加到trustChain中，最后返回trustChain
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }

    return [NSArray arrayWithArray:trustChain];
}
//取出服务器返回的所有证书的公钥
// 取出serverTrust中证书链上每个证书的公钥，并返回对应的该组公钥
static NSArray * AFPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust) {
    // 接下来的一小段代码和上面AFCertificateTrustChainForServerTrust函数的作用基本一致，都是为了获取到serverTrust中证书链上的所有证书，并依次遍历，取出公钥。
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);

        SecCertificateRef someCertificates[] = {certificate};
        CFArrayRef certificates = CFArrayCreate(NULL, (const void **)someCertificates, 1, NULL);

        SecTrustRef trust;
        // 根据给定的certificates和policy来生成一个trust对象
        __Require_noErr_Quiet(SecTrustCreateWithCertificates(certificates, policy, &trust), _out);

        SecTrustResultType result;
        // 使用SecTrustEvaluate来评估上面构建的trust
        __Require_noErr_Quiet(SecTrustEvaluate(trust, &result), _out);
        
        // 如果该trust符合X.509证书格式，那么先使用SecTrustCopyPublicKey获取到trust的公钥，再将此公钥添加到trustChain中
        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];

    _out:
        // 注意释放资源
        if (trust) {
            CFRelease(trust);
        }

        if (certificates) {
            CFRelease(certificates);
        }

        continue;
    }
    CFRelease(policy);
    
    // 返回对应的一组公钥
    return [NSArray arrayWithArray:trustChain];
}

#pragma mark -

@interface AFSecurityPolicy()
@property (readwrite, nonatomic, assign) AFSSLPinningMode SSLPinningMode;
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
@end

@implementation AFSecurityPolicy

//获取Bundle下的所有证书
+ (NSSet *)certificatesInBundle:(NSBundle *)bundle {
    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];

    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
    for (NSString *path in paths) {
        NSData *certificateData = [NSData dataWithContentsOfFile:path];
        [certificates addObject:certificateData];
    }

    return [NSSet setWithSet:certificates];
}

+ (NSSet *)defaultPinnedCertificates {
    static NSSet *_defaultPinnedCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        _defaultPinnedCertificates = [self certificatesInBundle:bundle];
    });

    return _defaultPinnedCertificates;
}

+ (instancetype)defaultPolicy {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = AFSSLPinningModeNone;

    return securityPolicy;
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:[self defaultPinnedCertificates]];
}

// 初始化AFSecurityPolicy对象的SSLPinningMode和pinnedCertificates两个属性
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;

    [securityPolicy setPinnedCertificates:pinnedCertificates];

    return securityPolicy;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.validatesDomainName = YES;

    return self;
}
// 此函数设置securityPolicy中的pinnedCertificates属性
// 注意还将对应的self.pinnedPublicKeys属性也设置了，该属性表示的是对应证书的公钥（与pinnedCertificates中的证书是一一对应的）
- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;

    if (self.pinnedCertificates) {
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = AFPublicKeyForCertificate(certificate);
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}

#pragma mark -

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain
{
    //表示如果此处允许使用自建证书（服务器自己弄的CA证书，非官方），并且还想验证domain是否有效(self.validatesDomainName == YES)，也就是说你想验证自建证书的domain是否有效。那么你必须使用pinnedCertificates（就是在客户端保存服务器端颁发的证书拷贝）才可以。但是你的SSLPinningMode为AFSSLPinningModeNone，表示你不使用SSL pinning，只跟浏览器一样在系统的信任机构列表里验证服务端返回的证书。所以当然你的客户端上没有你导入的pinnedCertificates，同样表示你无法验证该自建证书。所以都返回NO。最终结论就是要使用服务器端自建证书，那么就得将对应的证书拷贝到iOS客户端，并使用AFSSLPinningMode或AFSSLPinningModePublicKey
    if (domain && self.allowInvalidCertificates && self.validatesDomainName &&
        (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        // https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/OverridingSSLChainValidationCorrectly.html
        //  According to the docs, you should only trust your provided certs for evaluation.
        //  Pinned certificates are added to the trust. Without pinned certificates,
        //  there is nothing to evaluate against.
        //
        //  From Apple Docs:
        //          "Do not implicitly trust self-signed certificates as anchors (kSecTrustOptionImplicitAnchors).
        //           Instead, add your own (self-signed) CA certificate to the list of trusted anchors."
        NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
        return NO;
    }
    
    // 此处设置验证证书的策略
    NSMutableArray *policies = [NSMutableArray array];
     // 如果需要验证domain，那么就使用SecPolicyCreateSSL函数创建验证策略，其中第一个参数为true表示验证整个SSL证书链，第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致
    if (self.validatesDomainName) {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        // // 如果不需要验证domain，就使用默认的BasicX509验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    
    // 为serverTrust设置验证策略，即告诉客户端如何验证serverTrust
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    
    // 如果SSLPinningMode为 AFSSLPinningModeNone，表示你不使用SSL pinning，但是我允许自建证书，那么返回YES，或者使用AFServerTrustIsValid函数看看serverTrust是否可信任，如果信任，也返回YES
    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
    } else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
        // 既不允许自建证书，而且使用AFServerTrustIsValid函数又返回NO，那么该serverTrust就真的不能通过验证了
        return NO;
    }
    
    // 1.通过了根证书的验证
   // 2.allowInvalidCertificates = YES
    switch (self.SSLPinningMode) {
            
        // 理论上，上面那个部分已经解决了self.SSLPinningMode)为AFSSLPinningModeNone)等情况，所以此处再遇到，就直接返回NO
        case AFSSLPinningModeNone:
        default:
            return NO;
            // 这个模式表示用证书绑定(SSL Pinning)方式验证证书，需要客户端保存有服务端的证书拷贝
            // 注意客户端保存的证书存放在self.pinnedCertificates中
        case AFSSLPinningModeCertificate: { // 全部校验
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            
            for (NSData *certificateData in self.pinnedCertificates) {
                  // 这里使用SecCertificateCreateWithData函数对原先的pinnedCertificates做一些处理，保证返回的证书都是DER编码的X.509证书
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
             // 把本地的证书设为根证书，即服务器应该信任的证书
            // 将pinnedCertificates设置成需要参与验证的Anchor Certificate（锚点证书，通过SecTrustSetAnchorCertificates设置了参与校验锚点证书之后，假如验证的数字证书是这个锚点证书的子节点，即验证的数字证书是由锚点证书对应CA或子CA签发的，或是该证书本身，则信任该证书），具体就是调用SecTrustEvaluate来验证。
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
            
            // 校验能够信任
            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }

            // obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
             // 服务器端的证书链，注意此处返回的证书链顺序是从叶节点到根节点
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            //  判断本地证书和服务器证书是否相同
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                
                // 从服务器端证书链的根节点往下遍历，看看是否有与客户端的绑定证书一致的，有的话，就说明服务器端是可信的。因为遍历顺序正好相反，所以使用reverseObjectEnumerator
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            
            return NO;
        }
             // AFSSLPinningModePublicKey模式同样是用证书绑定(SSL Pinning)方式验证，客户端要有服务端的证书拷贝，只是验证时只验证证书里的公钥，不验证证书的有效期等信息。只要公钥是正确的，就能保证通信不会被窃听，因为中间人没有私钥，无法解开通过公钥加密的数据。
        case AFSSLPinningModePublicKey: {
            NSUInteger trustedPublicKeyCount = 0;
            // 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
            
            //依次遍历这些公钥，如果和客户端绑定证书的公钥一致，那么就给trustedPublicKeyCount加一
            for (id trustChainPublicKey in publicKeys) {
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            // trustedPublicKeyCount大于0说明服务器端中的某个证书和客户端绑定的证书公钥一致，认为服务器端是可信的
            return trustedPublicKeyCount > 0;
        }
    }
    
    return NO;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingPinnedPublicKeys {
    return [NSSet setWithObject:@"pinnedCertificates"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {

    self = [self init];
    if (!self) {
        return nil;
    }

    self.SSLPinningMode = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
    self.allowInvalidCertificates = [decoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    self.validatesDomainName = [decoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
    self.pinnedCertificates = [decoder decodeObjectOfClass:[NSArray class] forKey:NSStringFromSelector(@selector(pinnedCertificates))];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
    [coder encodeBool:self.allowInvalidCertificates forKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    [coder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
    [coder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFSecurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
    securityPolicy.SSLPinningMode = self.SSLPinningMode;
    securityPolicy.allowInvalidCertificates = self.allowInvalidCertificates;
    securityPolicy.validatesDomainName = self.validatesDomainName;
    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];

    return securityPolicy;
}

@end
