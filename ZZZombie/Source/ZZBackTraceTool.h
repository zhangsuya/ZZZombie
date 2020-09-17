//
//  ZZBackTraceTool.h
//  ZZZombie
//
//  Created by 张苏亚 on 2020/9/4.
//  Copyright © 2020 张苏亚. All rights reserved.
//

#import <Foundation/Foundation.h>
namespace BackTraceTool
{
    NSString *_bs_symbolbacktraceOfFrame(uintptr_t backtraceBuffer[],int i);
}
NS_ASSUME_NONNULL_BEGIN

@interface ZZBackTraceTool : NSObject

@end

NS_ASSUME_NONNULL_END
