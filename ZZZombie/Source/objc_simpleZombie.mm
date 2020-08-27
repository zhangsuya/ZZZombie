//
//  objc_simpleZombie.m
//  CCZombie
//
//  Created by 张苏亚 on 2020/5/9.
//  Copyright © 2020 张苏亚. All rights reserved.
//

#import "objc_simpleZombie.h"
#import <string.h>

#import <execinfo.h>
#import <objc/runtime.h>

#import <algorithm>
#import <pthread.h>

#import <iostream>
#import <chrono>
#import <thread>
#import <mutex>

__attribute__((objc_root_class))
@interface SYSimpoleZombie
{
    Class isa;
    
}
@end

@interface SYFatZombie : SYSimpoleZombie
{
    @public
    Class wasa;
}
@end


namespace  ObjcEvilDoers {




    // The depth of backtrace to store with zombies.  This directly influences
    // the amount of memory required to track zombies, so should be kept as
    // small as is useful.  Unfortunately, too small and it won't poke through
    // deep autorelease and event loop stacks.
    // NOTE(shess): Breakpad currently restricts values to 255 bytes.  The
    // trace is hex-encoded with "0x" prefix and " " separators, meaning
    // the maximum number of 32-bit items which can be encoded is 23.
    const size_t kBacktraceDepth = 20;
    // The original implementation for |-[NSObject dealloc]|.
    #if OBJC_OLD_DISPATCH_PROTOTYPES
    using RealIMP = IMP;
    #else
    // With !OBJC_OLD_DISPATCH_PROTOTYPES the runtime hasn't changed and IMP is
    // still what it always was, but the SDK is hiding the details now outside the
    // objc runtime. It is safe to define |RealIMP| to match the older definition of
    // |IMP|.
    using RealIMP = id (*)(id, SEL, ...);
    #endif

    RealIMP g_originalDeallocIMP = NULL;
    static auto *_lock = (new std::mutex);

    // Classes which freed objects become.  |g_fatZombieSize| is the
    // minimum object size which can be made into a fat zombie (which can
    // remember which class it was before free, even after falling off the
    // treadmill).
    Class g_simpleZombieClass = Nil;  // cached [SYSimpoleZombie class]
    Class g_fatZombieClass = Nil;  // cached [SYFatZombie class]
    size_t g_fatZombieSize = 0;

    // Whether to zombie all freed objects, or only those which return YES
    // from |-shouldBecomeCrZombie|.
    BOOL g_zombieAllObjects = NO;

    // Protects |g_zombieCount|, |g_zombieIndex|, and |g_zombies|.
    //base::Lock& GetLock() {
    //  static auto* lock = new base::Lock();
    //  return *lock;
    //}

    // How many zombies to keep before freeing, and the current head of
    // the circular buffer.
    size_t g_zombieCount = 0;
    size_t g_zombieIndex = 0;
    typedef struct {
      id object;   // The zombied object.
      Class wasa;  // Value of |object->isa| before we replaced it.
      void* trace[kBacktraceDepth];  // Backtrace at point of deallocation.
      size_t traceDepth;             // Actual depth of trace[].
    } ZombieRecord;

    ZombieRecord* g_zombies = NULL;
    // Replacement |-dealloc| which turns objects into zombies and places
    // them into |g_zombies| to be freed later.
    void ZombieDealloc(id self, SEL _cmd) {
        
        if ((!g_zombieAllObjects && ![self shouldBecomeCrZombie])) {
          g_originalDeallocIMP(self, _cmd);
          return;
        }else if ([NSStringFromClass([self class]) hasPrefix:@"OS_"])
        {
            g_originalDeallocIMP(self, _cmd);
            return;
        }
        
        Class wasa = object_getClass(self);
        const size_t size = class_getInstanceSize(wasa);

        // Destroy the instance by calling C++ destructors and clearing it
        // to something unlikely to work well if someone references it.
        // NOTE(shess): |object_dispose()| will call this again when the
        // zombie falls off the treadmill!  But by then |isa| will be a
        // class without C++ destructors or associative references, so it
        // won't hurt anything.
          
        objc_destructInstance(self);
//        free(object_getClass(self));
//            If the instance is big enough, make it into a fat zombie and have
          // it remember the old |isa|.  Otherwise make it a regular zombie.
          // Setting |isa| rather than using |object_setClass()| because that
          // function is implemented with a memory barrier.  The runtime's
          // |_internal_object_dispose()| (in objc-class.m) does this, so it
          // should be safe (messaging free'd objects shouldn't be expected to
          // be thread-safe in the first place).
        #pragma clang diagnostic push  // clang warns about direct access to isa.
        #pragma clang diagnostic ignored "-Wdeprecated-objc-isa-usage"
          if (size >= g_fatZombieSize) {
            self->isa = g_fatZombieClass;
            static_cast<SYFatZombie*>(self)->wasa = wasa;
          } else {
            self->isa = g_simpleZombieClass;
          }
        #pragma clang diagnostic pop
        ZombieRecord zombieToFree = {self, wasa};
          zombieToFree.traceDepth =
              std::max(backtrace(zombieToFree.trace, kBacktraceDepth), 0);

          // Don't involve the lock when creating zombies without a treadmill.
          if (g_zombieCount > 0) {
              std::lock_guard<std::mutex> l(*_lock);

            // Check the count again in a thread-safe manner.
            if (g_zombieCount > 0) {
              // Put the current object on the treadmill and keep the previous
              // occupant.
              std::swap(zombieToFree, g_zombies[g_zombieIndex]);

              // Bump the index forward.
              g_zombieIndex = (g_zombieIndex + 1) % g_zombieCount;
            }
          }

          // Do the free out here to prevent any chance of deadlock.
          if (zombieToFree.object)
            object_dispose(zombieToFree.object);
        
    }
    // Search the treadmill for |object| and fill in |*record| if found.
    // Returns YES if found.
    BOOL GetZombieRecord(id object, ZombieRecord* record) {
      // Holding the lock is reasonable because this should be fast, and
      // the process is going to crash presently anyhow.
        std::lock_guard<std::mutex> l(*_lock);

      for (size_t i = 0; i < g_zombieCount; ++i) {
        if (g_zombies[i].object == object) {
          *record = g_zombies[i];
          return YES;
        }
      }
      return NO;
    }

    // Dump the symbols.  This is pulled out into a function to make it
    // easy to use DCHECK to dump only in debug builds.
    BOOL DumpDeallocTrace(const void* const* array, int size) {
      const char message[] = "Backtrace from -dealloc:\n";
    //  StackTrace(array, size).Print();

      return YES;
    }

    void ZombieObjectCrash(id object, SEL aSelector, SEL viaSelector) {
        ZombieRecord record;
        BOOL found = GetZombieRecord(object, &record);

        // The object's class can be in the zombie record, but if that is
        // not available it can also be in the object itself (in most cases).
        Class wasa = Nil;
        if (found) {
          wasa = record.wasa;
        } else if (object_getClass(object) == g_fatZombieClass) {
          wasa = static_cast<SYFatZombie*>(object)->wasa;
        }
        const char* wasaName = (wasa ? class_getName(wasa) : "<unknown>");
//        NSLog(@"%@ %@",object,aSelector);
    }
    
    BOOL ZombieInit()
    {
        static BOOL initialized = NO;
        if (initialized) {
            return YES;
        }
        
        Class rootClass = [NSObject class];
        g_originalDeallocIMP = reinterpret_cast<RealIMP>(class_getMethodImplementation(rootClass, @selector(dealloc)));
        g_simpleZombieClass = objc_getClass("SYSimpoleZombie");
        g_fatZombieClass = objc_getClass("SYFatZombie");
        g_fatZombieSize = class_getInstanceSize(g_fatZombieClass);
        
        if (!g_originalDeallocIMP||!g_simpleZombieClass||!g_fatZombieClass) {
            return NO;
        }
        initialized = YES;
        return YES;
    }
}

@implementation SYSimpoleZombie

// The Objective-C runtime needs to be able to call this successfully.
+ (void)initialize {
}

// Any method not explicitly defined will end up here, forcing a
// crash.
- (id)forwardingTargetForSelector:(SEL)aSelector {
    ObjcEvilDoers::ZombieObjectCrash(self, aSelector, NULL);
  return nil;
}

// Override a few methods often used for dynamic dispatch to log the
// message the caller is attempting to send, rather than the utility
// method being used to send it.
- (BOOL)respondsToSelector:(SEL)aSelector {
    ObjcEvilDoers::ZombieObjectCrash(self, aSelector, _cmd);
  return NO;
}

- (id)performSelector:(SEL)aSelector {
    ObjcEvilDoers::ZombieObjectCrash(self, aSelector, _cmd);
  return nil;
}

- (id)performSelector:(SEL)aSelector withObject:(id)anObject {
    ObjcEvilDoers::ZombieObjectCrash(self, aSelector, _cmd);
  return nil;
}

- (id)performSelector:(SEL)aSelector
           withObject:(id)anObject
           withObject:(id)anotherObject {
    ObjcEvilDoers::ZombieObjectCrash(self, aSelector, _cmd);
  return nil;
}

- (void)performSelector:(SEL)aSelector
             withObject:(id)anArgument
             afterDelay:(NSTimeInterval)delay {
    ObjcEvilDoers::ZombieObjectCrash(self, aSelector, _cmd);
}


@end


@implementation SYFatZombie



@end

@implementation NSObject (SimpleZombie)

- (BOOL)shouldBecomeCrZombie {
  return NO;
}

@end


namespace ObjcEvilDoers {

    bool  SimpleZombieEnable(bool zombieAllObjects, size_t zombieCount)
    {
        if (![NSThread isMainThread]) {
            return NO;
        }
        if (!ZombieInit()) {
            return NO;
        }
        g_zombieAllObjects = zombieAllObjects;
        Method m =class_getInstanceMethod([NSObject class], @selector(dealloc));
        if (!m) {
            return NO;
        }
        const RealIMP preDeallocIMP = reinterpret_cast<RealIMP>(method_setImplementation(m, reinterpret_cast<IMP>(ZombieDealloc)));
        if (preDeallocIMP == g_originalDeallocIMP || preDeallocIMP == reinterpret_cast<RealIMP>(ZombieDealloc)) {
            return false;
        }
        // Grab the current set of zombies.  This is thread-safe because
          // only the main thread can change these.
        const size_t oldCount = g_zombieCount;
        ZombieRecord* oldZombies = g_zombies;

          {
              std::lock_guard<std::mutex> l(*_lock);
            // Save the old index in case zombies need to be transferred.
              size_t oldIndex = g_zombieIndex;

            // Create the new zombie treadmill, disabling zombies in case of
            // failure.
              g_zombieIndex = 0;
              g_zombieCount = zombieCount;
              g_zombies = NULL;
              if (g_zombieCount) {
                  g_zombies =
                  static_cast<ZombieRecord*>(calloc(g_zombieCount, sizeof(*g_zombies)));
                  if (!g_zombies) {
        //        NOTREACHED();
                      g_zombies = oldZombies;
                      g_zombieCount = oldCount;
                      g_zombieIndex = oldIndex;
                SimpleZombieDisable();
                return false;
              }
            }

            // If the count is changing, allow some of the zombies to continue
            // shambling forward.
            const size_t sharedCount = std::min(oldCount, zombieCount);
            if (sharedCount) {
              // Get index of the first shared zombie.
              oldIndex = (oldIndex + oldCount - sharedCount) % oldCount;

                for (; g_zombieIndex < sharedCount; ++ g_zombieIndex) {
        //        DCHECK_LT(g_zombieIndex, g_zombieCount);
        //        DCHECK_LT(oldIndex, oldCount);
                    std::swap(g_zombies[g_zombieIndex], oldZombies[oldIndex]);
                oldIndex = (oldIndex + 1) % oldCount;
              }
                g_zombieIndex %= g_zombieCount;
            }
          }

          // Free the old treadmill and any remaining zombies.
          if (oldZombies) {
            for (size_t i = 0; i < oldCount; ++i) {
              if (oldZombies[i].object)
                object_dispose(oldZombies[i].object);
            }
            free(oldZombies);
          }

        return YES;
    }

    // Disable zombies.
    void  SimpleZombieDisable()
    {
        if (![NSThread isMainThread]) {
            return;
        }
        if (!g_originalDeallocIMP) {
            return;
        }
        Method m = class_getInstanceMethod([NSObject class], @selector(dealloc));
        method_setImplementation(m, reinterpret_cast<IMP>(g_originalDeallocIMP));
    // Can safely grab this because it only happens on the main thread.
        const size_t oldCount = g_zombieCount;
        ZombieRecord* oldZombies = g_zombies;

      {
          std::lock_guard<std::mutex> l(*_lock);

          g_zombieCount = 0;
          g_zombies = NULL;
      }

      // Free any remaining zombies.
      if (oldZombies) {
        for (size_t i = 0; i < oldCount; ++i) {
          if (oldZombies[i].object)
            object_dispose(oldZombies[i].object);
        }
        free(oldZombies);
      }
    }
    
}
