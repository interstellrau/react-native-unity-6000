#import "RNUnityView.h"
#ifdef DEBUG
#include <mach-o/ldsyms.h>
#endif
#import <objc/message.h>

NSString *bundlePathStr = @"/Frameworks/UnityFramework.framework";
int gArgc = 1;

static NSDictionary *appLaunchOpts;

#pragma mark - Unity Loader

static UnityFramework* UnityFrameworkLoad(void) {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    bundlePath = [bundlePath stringByAppendingString:bundlePathStr];

    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (![bundle isLoaded]) {
        [bundle load];
    }

    UnityFramework *ufw = [bundle.principalClass getInstance];
    if (![ufw appController]) {
#ifdef DEBUG
        [ufw setExecuteHeader:&_mh_dylib_header];
#else
        [ufw setExecuteHeader:&_mh_execute_header];
#endif
    }
    [ufw setDataBundleId:[bundle.bundleIdentifier cStringUsingEncoding:NSUTF8StringEncoding]];
    return ufw;
}

@implementation RNUnityView

#pragma mark - Helpers

- (BOOL)unityIsInitialized {
    return [self ufw] && [[self ufw] appController];
}

#pragma mark - Unity Initialization

- (void)initUnityModule {
    @try {
        if([self unityIsInitialized]) {
            return;
        }

        [self setUfw: UnityFrameworkLoad()];
        [[self ufw] registerFrameworkListener: self];

        unsigned count = (int) [[[NSProcessInfo processInfo] arguments] count];
        char **array = (char **)malloc((count + 1) * sizeof(char*));

        for (unsigned i = 0; i < count; i++)
        {
             array[i] = strdup([[[[NSProcessInfo processInfo] arguments] objectAtIndex:i] UTF8String]);
        }
        array[count] = NULL;

        [[self ufw] runEmbeddedWithArgc: gArgc argv: array appLaunchOpts: appLaunchOpts];
        [[self ufw] appController].quitHandler = ^(){ NSLog(@"AppController.quitHandler called"); };
        [self.ufw.appController.rootView removeFromSuperview];

        if (@available(iOS 13.0, *)) {
            [[[[self ufw] appController] window] setWindowScene: nil];
        } else {
            [[[[self ufw] appController] window] setScreen: nil];
        }

        [[[[self ufw] appController] window] addSubview: self.ufw.appController.rootView];
        [[[[self ufw] appController] window] makeKeyAndVisible];
        [[[[[[self ufw] appController] window] rootViewController] view] setNeedsLayout];

        [NSClassFromString(@"FrameworkLibAPI") registerAPIforNativeCalls:self];
    }
    @catch (NSException *e) {
        NSLog(@"%@",e);
    }
}

#pragma mark - Reset / Unload Unity

- (void)resetUnityFramework {
    if ([self unityIsInitialized]) {
        NSLog(@"[RNUnityView] Unloading Unity...");
        [[self ufw] unregisterFrameworkListener:self];
        [[self ufw] unloadApplication];
        [self setUfw:nil];
    }

    UnityFramework *ufw = [UnityFramework getInstance];
    if (ufw && [UnityFramework respondsToSelector:@selector(setInstance:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(UnityFramework.class, @selector(setInstance:), nil);
    }

    NSLog(@"[RNUnityView] Unity reset — ready for reinit.");
}

- (void)unloadUnity {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *main = [[[UIApplication sharedApplication] delegate] window];
        if (main) {
            [main makeKeyAndVisible];
        }
        [self resetUnityFramework];
    });
}

#pragma mark - Pause / Resume

- (void)pauseUnity:(BOOL)pause {
    if ([self unityIsInitialized]) {
        [[self ufw] pause:pause];
    }
}

#pragma mark - UIView Layout

- (void)layoutSubviews {
   [super layoutSubviews];

   // Wait for real, non-zero bounds before booting Unity. Booting at a zero
   // size triggers Unity's `MTLTextureDescriptor has width of zero` crash
   // (see "Known issues" in the README).
   if (self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
      return;
   }

   if (![self unityIsInitialized]) {
      [self initUnityModule];
   }

   if ([self unityIsInitialized]) {
      UIView *rootView = self.ufw.appController.rootView;
      rootView.frame = self.bounds;
      // Only parent the Unity root view once; re-adding it on every layout
      // pass causes needless re-parenting and flicker.
      if (rootView.superview != self) {
         [self addSubview:rootView];
      }
   }
}

#pragma mark - React Native Bridge

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onUnityMessage", @"onPlayerUnload", @"onPlayerQuit"];
}

- (void)sendMessageToMobileApp:(NSString *)message {
    if (self.onUnityMessage) {
        NSDictionary *data = @{ @"message": message ?: @"" };
        self.onUnityMessage(data);
    }
}

- (void)postMessage:(NSString *)gameObject methodName:(NSString *)methodName message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self ufw] sendMessageToGOWithName:[gameObject UTF8String]
                                functionName:[methodName UTF8String]
                                     message:[message UTF8String]];
    });
}

#pragma mark - Unity Lifecycle Events

- (void)unityDidUnload:(NSNotification *)notification {
    NSLog(@"[RNUnityView] Unity did unload.");
    if ([self unityIsInitialized]) {
        [[self ufw] unregisterFrameworkListener:self];
        [self setUfw:nil];
    }
    if (self.onPlayerUnload) self.onPlayerUnload(nil);
}

- (void)unityDidQuit:(NSNotification *)notification {
    NSLog(@"[RNUnityView] Unity did quit.");
    if ([self unityIsInitialized]) {
        [[self ufw] unregisterFrameworkListener:self];
        [self setUfw:nil];
    }
    if (self.onPlayerQuit) self.onPlayerQuit(nil);
}

#pragma mark - React View Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];

    // Unity is booted lazily in -layoutSubviews once the view has real
    // (non-zero) bounds. Booting here would start Unity at CGRectZero and
    // risk the zero-width Metal texture crash.

    return self;
}

@end
