#import <Foundation/Foundation.h>
#import <sys/types.h>
NS_ASSUME_NONNULL_BEGIN
int TRSpawn(NSString *executable, NSArray<NSString *> *arguments, BOOL root, BOOL wait);
pid_t TRLocationPID(void);
NSString *TRProcessIdentity(pid_t pid);
NSString *TRProcessPath(pid_t pid);
int TRProtectKeeper(int32_t *priority);
int TRCheckKeeperProtection(int32_t *priority);
NS_ASSUME_NONNULL_END
