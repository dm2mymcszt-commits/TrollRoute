// Persona and Jetsam technique adapted from TrollSpeed (MIT); see notices.
#import "KeeperNative.h"
#import <spawn.h>
#import <fcntl.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>
#import <TargetConditionals.h>
extern char **environ;

int TRSpawn(NSString *executable, NSArray<NSString *> *arguments, BOOL root, BOOL wait) {
#if TARGET_OS_SIMULATOR
    return ENOTSUP;
#else
    posix_spawnattr_t attr;
    int result = posix_spawnattr_init(&attr);
    if (result) return result;
    if (root) {
        int (*persona)(const posix_spawnattr_t *, uid_t, uint32_t) = dlsym(RTLD_DEFAULT, "posix_spawnattr_set_persona_np");
        int (*uid)(const posix_spawnattr_t *, uid_t) = dlsym(RTLD_DEFAULT, "posix_spawnattr_set_persona_uid_np");
        int (*gid)(const posix_spawnattr_t *, gid_t) = dlsym(RTLD_DEFAULT, "posix_spawnattr_set_persona_gid_np");
        if (!persona || !uid || !gid) result = ENOTSUP;
        if (!result) result = persona(&attr, 99, 1);
        if (!result) result = uid(&attr, 0);
        if (!result) result = gid(&attr, 0);
    }
    if (!result) result = posix_spawnattr_setpgroup(&attr, 0);
    if (!result) result = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObject:executable];
    [args addObjectsFromArray:arguments];
    char **argv = calloc(args.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < args.count; i++) argv[i] = strdup(args[i].UTF8String);
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    for (int fd = 0; fd < 3; fd++) posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd ? O_WRONLY : O_RDONLY, 0);
    pid_t child = 0;
    if (!result) result = posix_spawn(&child, executable.fileSystemRepresentation, &actions, &attr, argv, environ);
    posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr);
    for (NSUInteger i = 0; i < args.count; i++) free(argv[i]); free(argv);
    if (result) return result;
    if (!wait) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ int status; while (waitpid(child, &status, 0) < 0 && errno == EINTR) {} });
        return 0;
    }
    // Bound a hung control helper; never block the application indefinitely.
    for (int i = 0; i < 200; i++) {
        int status = 0; pid_t rc = waitpid(child, &status, WNOHANG);
        if (rc == child) return WIFEXITED(status) ? WEXITSTATUS(status) : EIO;
        if (rc < 0 && errno != EINTR) return errno;
        usleep(25000);
    }
    kill(child, SIGKILL); waitpid(child, NULL, 0); return ETIMEDOUT;
#endif
}

static BOOL TRProcess(pid_t pid, struct kinfo_proc *info) {
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid}; size_t length = sizeof(*info);
    return sysctl(mib, 4, info, &length, NULL, 0) == 0 && length == sizeof(*info);
}
NSString *TRProcessIdentity(pid_t pid) {
    struct kinfo_proc info = {0};
    if (pid <= 0 || !TRProcess(pid, &info)) return @"";
    return [NSString stringWithFormat:@"%d:%lld:%d", pid, (long long)info.kp_proc.p_starttime.tv_sec, info.kp_proc.p_starttime.tv_usec];
}
NSString *TRProcessPath(pid_t pid) {
    int (*path)(int, void *, uint32_t) = dlsym(RTLD_DEFAULT, "proc_pidpath");
    char buffer[4096] = {0};
    return path && path(pid, buffer, sizeof(buffer)) > 0 ? [NSString stringWithUTF8String:buffer] : @"";
}
pid_t TRLocationPID(void) {
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0}; size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0)) return 0;
    size += 32 * sizeof(struct kinfo_proc);
    struct kinfo_proc *entries = calloc(1, size);
    if (!entries) return 0;
    pid_t result = 0;
    if (!sysctl(mib, 4, entries, &size, NULL, 0)) {
        for (size_t i = 0; i < size / sizeof(*entries); i++) {
            if (!strcmp(entries[i].kp_proc.p_comm, "locationd")) { result = entries[i].kp_proc.p_pid; break; }
        }
    }
    free(entries); return result;
}
int TRProtectKeeper(void) {
#if TARGET_OS_SIMULATOR
    return ENOTSUP;
#else
    int (*control)(uint32_t, int32_t, uint32_t, void *, size_t) = dlsym(RTLD_DEFAULT, "memorystatus_control");
    int (*dirty)(pid_t, uint32_t) = dlsym(RTLD_DEFAULT, "proc_track_dirty");
    if (!control || !dirty) return ENOTSUP;
    struct { int32_t priority; uint64_t userData; } priority = {19, 0};
    int first = 0;
    if (control(2, getpid(), 0, &priority, sizeof(priority)) < 0) first = errno;
    const uint32_t commands[] = {5, 6, 16, 18};
    const uint32_t flags[] = {UINT32_MAX, 0, 0, 0};
    for (int i = 0; i < 4; i++) if (control(commands[i], getpid(), flags[i], NULL, 0) < 0 && !first) first = errno;
    int rc = dirty(getpid(), 0); if (rc && !first) first = rc;
    return first;
#endif
}
