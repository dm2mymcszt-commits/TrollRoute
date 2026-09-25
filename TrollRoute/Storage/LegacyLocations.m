#import "LegacyLocations.h"
// Narrow read-only declarations for old data discovery. No install/uninstall APIs.
@interface LSBundleProxy : NSObject
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end
@interface LSApplicationProxy : LSBundleProxy
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSDictionary *groupContainerURLs;
@property (getter=isInstalled, nonatomic, readonly) BOOL installed;
@end
@interface MCMContainer : NSObject
+ (id)containerWithIdentifier:(id)identifier createIfNecessary:(BOOL)create existed:(BOOL *)existed error:(id *)error;
@property (nonatomic, readonly) NSURL *url;
@end
#import <dlfcn.h>

NSDictionary<NSString *, id> *TRLegacyLocations(void) {
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
            return @{@"error": @"The installed-app database is unavailable."};
        }
        LSApplicationProxy *proxy = [(id)proxyClass applicationProxyForIdentifier:@"com.son3ra1n.andromeda"];
        // A cached bundle URL can outlive uninstall. Only current registration
        // enables import; old files must never become a launch dependency.
        BOOL installed = proxy.installed;
        if (!installed) return @{@"installed": @NO};
        NSMutableArray *paths = [NSMutableArray arrayWithObject:@"/var/mobile/Library/Preferences/com.son3ra1n.andromeda.plist"];
        NSURL *container = proxy.dataContainerURL;
        if (container) {
            [paths addObject:[[container URLByAppendingPathComponent:@"Library/Preferences/com.son3ra1n.andromeda.plist"] path]];
        }
        NSURL *group = proxy.groupContainerURLs[@"group.live.cclerc.geraniumBookmarks"];
        if (!group) {
            // Read-only discovery of the installed old app's existing group.
            dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_LAZY);
            Class sharedClass = NSClassFromString(@"MCMSharedDataContainer");
            if ([sharedClass respondsToSelector:@selector(containerWithIdentifier:createIfNecessary:existed:error:)]) {
                BOOL existed = NO;
                id error = nil;
                MCMContainer *existing = [(id)sharedClass containerWithIdentifier:@"group.live.cclerc.geraniumBookmarks"
                    createIfNecessary:NO existed:&existed error:&error];
                if (existed) group = existing.url;
            }
        }
        NSMutableDictionary *result = [@{@"installed": @(installed), @"preferences": paths} mutableCopy];
        if (group) result[@"favorites"] = [[group URLByAppendingPathComponent:@"Library/Preferences/group.live.cclerc.geraniumBookmarks.plist"] path];
        return result;
    } @catch (NSException *exception) {
        return @{@"error": @"Could not inspect the previous app's existing containers."};
    }
}
