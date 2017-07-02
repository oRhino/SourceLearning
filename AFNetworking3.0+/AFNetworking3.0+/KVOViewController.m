//
//  KVOViewController.m
//  AFNetworking3.0+
//
//  Created by Rhino on 2017/6/29.
//  Copyright © 2017年 Rhino. All rights reserved.
//

#import "KVOViewController.h"

static NSInteger kCount = 0;

@interface KVOViewController ()

@property (nonatomic, copy) NSString *name;

@end

@implementation KVOViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //options 中的参数和observerValueForKeyPath:ofObject:change:context:中的change字典有关，如果提供NSKeyValueObservingOptionNew和NSKeyValueObservingOptionOld，则change字典中会提供属性值变化前和变化后的值。context参数可以是C指针也可以是对象的引用。在observerValueForKeyPath:ofObject:change:context:调用的时候context会可能被用到，主要是用来标记当前通知的上下文或者提供一些其他信息数据，几乎很少用一般为NULL。
    [self addObserver:self forKeyPath:@"name" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:(__bridge void * _Nullable)(self)];
    
}


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    
    self.name = [NSString stringWithFormat:@"%ld",(long)kCount++];
}

//其中change参数是一个字典，包含了注册时候提供的登记的键，例如NSKeyValueChangeOldKey, NSKeyValueChangeNewKey。如果被观察属性还是to-many relationship的类型，则NSKeyValueChangeInsertion, NSKeyValueChangeRemoval, NSKeyValueChangeReplacement表示当其内容有新增，移除，替换的变动信息。

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    
    NSLog(@"%@",context);
    
    if ([keyPath isEqualToString:@"name"]) {
//        [self.name setValue:[NSString stringWithFormat:@"%ld",(long)kCount++] forKey:NSKeyValueChangeNewKey];
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    NSLog(@"%@",self.name);
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
