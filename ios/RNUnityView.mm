#import "RNUnityView.h"
#ifdef DEBUG
#include <mach-o/ldsyms.h>
#endif
#import <objc/message.h>

NSString *bundlePathStr = @"/Frameworks/UnityFramework.framework";
int gArgc = 1;

static NSDictionary *appLaunchOpts;
static RNUnityView *sharedInstance = nil;
static BOOL sUnityBootStarted = NO;

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

- (void)initUnityModuleOnMainRunloop {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self initUnityModuleOnMainRunloop];
        });
        return;
    }

    if ([self unityIsInitialized]) {
        NSLog(@"[RNUnityView] Unity already initialized — skipping duplicate start.");
        return;
    }

    if (sUnityBootStarted) {
        NSLog(@"[RNUnityView] Unity boot already in progress — skipping.");
        return;
    }

    sUnityBootStarted = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                NSLog(@"[RNUnityView] Loading UnityFramework bundle...");
                [self setUfw:UnityFrameworkLoad()];
                [[self ufw] registerFrameworkListener:self];

                unsigned count = (unsigned)[[[NSProcessInfo processInfo] arguments] count];
                char **argv = (char **)malloc((count + 1) * sizeof(char *));
                for (unsigned i = 0; i < count; i++) {
                    argv[i] = strdup([[[[NSProcessInfo processInfo] arguments] objectAtIndex:i] UTF8String]);
                }
                argv[count] = NULL;

                NSLog(@"[RNUnityView] Starting Unity instance...");
                [[self ufw] runEmbeddedWithArgc:gArgc argv:argv appLaunchOpts:appLaunchOpts];
                [[self ufw] appController].quitHandler = ^(){};

                [self.ufw.appController.rootView removeFromSuperview];

                if (@available(iOS 13.0, *)) {
                    [[[[self ufw] appController] window] setWindowScene:nil];
                } else {
                    [[[[self ufw] appController] window] setScreen:nil];
                }

                [[[[self ufw] appController] window] addSubview:self.ufw.appController.rootView];
                [[[[self ufw] appController] window] makeKeyAndVisible];
                [[[[[[self ufw] appController] window] rootViewController] view] setNeedsLayout];

                [NSClassFromString(@"FrameworkLibAPI") registerAPIforNativeCalls:self];

                NSLog(@"[RNUnityView] Unity initialization complete.");
            }
            @catch (NSException *exception) {
                NSLog(@"[RNUnityView] Exception during Unity init: %@", exception);
                sUnityBootStarted = NO;
            }
        }
    });
}

#pragma mark - Reset / Unload Unity

- (void)resetUnityFramework {
    if ([self unityIsInitialized]) {
        NSLog(@"[RNUnityView] Unloading Unity...");
        [[self ufw] unregisterFrameworkListener:self];
        [[self ufw] unloadApplication];
        [self setUfw:nil];
    }

    sUnityBootStarted = NO;
    sharedInstance = nil;

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

#pragma mark - UIView Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if ([self unityIsInitialized]) {
        self.ufw.appController.rootView.frame = self.bounds;
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self addSubview:self.ufw.appController.rootView];
            });
        } else {
            [self addSubview:self.ufw.appController.rootView];
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
    sUnityBootStarted = NO;
    if (self.onPlayerUnload) self.onPlayerUnload(nil);
}

- (void)unityDidQuit:(NSNotification *)notification {
    NSLog(@"[RNUnityView] Unity did quit.");
    if ([self unityIsInitialized]) {
        [[self ufw] unregisterFrameworkListener:self];
        [self setUfw:nil];
    }
    sUnityBootStarted = NO;
    if (self.onPlayerQuit) self.onPlayerQuit(nil);
}

#pragma mark - React View Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSLog(@"[RNUnityView] initWithFrame — ensuring Unity (re)start.");

        // Force reinit each time UnityView mounts
        sUnityBootStarted = NO;
        [self setUfw:nil];
        sharedInstance = self;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self initUnityModuleOnMainRunloop];
        });
    }
    return self;
}

@end
