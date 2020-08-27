//
//  objc_simpleZombie.h
//  CCZombie
//
//  Created by 张苏亚 on 2020/5/9.
//  Copyright © 2020 张苏亚. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <stddef.h>
namespace ObjcEvilDoers {


// Enable zombie object debugging. This implements a variant of Apple's
// NSZombieEnabled which can help expose use-after-free errors where messages
// are sent to freed Objective-C objects in production builds.
//
// Returns NO if it fails to enable.
//
// When |zombieAllObjects| is YES, all objects inheriting from
// NSObject become zombies on -dealloc.  If NO, -shouldBecomeCrZombie
// is queried to determine whether to make the object a zombie.
//
// |zombieCount| controls how many zombies to store before freeing the
// oldest.  Set to 0 to free objects immediately after making them
// zombies.
bool  SimpleZombieEnable(bool zombieAllObjects, size_t zombieCount);

// Disable zombies.
void  SimpleZombieDisable();

}
NS_ASSUME_NONNULL_BEGIN

@interface NSObject (SimpleZombie)
- (BOOL)shouldBecomeCrZombie;
@end

NS_ASSUME_NONNULL_END
