//
//  ViewController.m
//  ZZZombie
//
//  Created by 张苏亚 on 2020/8/27.
//  Copyright © 2020 张苏亚. All rights reserved.
//

#import "ViewController.h"
#import <objc/runtime.h>
#import "objc_simpleZombie.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    {
        ViewController *vc = [ViewController new];
        [vc release];
#warning 野指针
        [vc xxcccc];

    }
}

-(void)xxcccc
{
    
}
@end
