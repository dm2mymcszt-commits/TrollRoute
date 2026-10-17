// Private memorystatus ABI, verified against Apple XNU 8019, 8792 and 10002.
// Keep the decision and verification code shared with executable host tests.
#ifndef TR_KEEPER_PROTECTION_H
#define TR_KEEPER_PROTECTION_H
#include <stdint.h>
#include <stddef.h>
#include <errno.h>

typedef int (*TRMemoryControl)(uint32_t, int32_t, uint32_t, void *, size_t);
typedef int (*TRDirtyControl)(int32_t, uint32_t);
typedef struct { int32_t priority; uint64_t userData; } TRPriorityRequest;
typedef struct {
    int32_t pid;
    int32_t priority;
    uint64_t userData;
    int32_t limit;
    uint32_t state;
} TRPriorityEntry;
_Static_assert(sizeof(TRPriorityRequest) == 16, "memorystatus request ABI");
_Static_assert(sizeof(TRPriorityEntry) == 24, "memorystatus entry ABI");

static inline int32_t TRCriticalPriority(int darwinMajor) {
    // iOS 15 uses Darwin 21; iOS 16/17 use Darwin 22/23.
    // On the newer kernels, 19 is inside the aging range and becomes IDLE (0),
    // even though SET_PRIORITY_PROPERTIES returns success. Revision stays 2.
    if (darwinMajor == 21) return 19;
    if (darwinMajor == 22 || darwinMajor == 23) return 190;
    return -1;
}

static inline int TRReadPriority(TRMemoryControl control, int32_t pid, int32_t *actual) {
    *actual = -1;
    if (!control) return ENOTSUP;
    TRPriorityEntry entry = {0};
    int rc = control(1, pid, 0, &entry, sizeof(entry));
    if (rc < 0) return errno ? errno : EIO;
    if (rc != sizeof(entry) || entry.pid != pid) return EIO;
    *actual = entry.priority;
    return 0;
}

static inline int TREnsurePriority(TRMemoryControl control, int32_t pid,
                                   int darwinMajor, int32_t *actual) {
    *actual = -1;
    int32_t target = TRCriticalPriority(darwinMajor);
    if (target < 0 || !control) return ENOTSUP;
    int rc = TRReadPriority(control, pid, actual);
    if (rc) return rc;
    if (*actual == target) return 0;
    TRPriorityRequest request = {target, 0};
    if (control(2, pid, 0, &request, sizeof(request)) < 0) return errno ? errno : EIO;
    rc = TRReadPriority(control, pid, actual);
    if (rc) return rc;
    return *actual == target ? 0 : EACCES;
}

static inline int TRConfigureProtection(TRMemoryControl control, TRDirtyControl dirty,
                                        int32_t pid, int darwinMajor, int32_t *actual) {
    *actual = -1;
    if (!control || !dirty || TRCriticalPriority(darwinMajor) < 0) return ENOTSUP;
    int first = 0;
    const uint32_t commands[] = {5, 6, 16, 18};
    const uint32_t flags[] = {UINT32_MAX, 0, 0, 0};
    for (int i = 0; i < 4; i++) {
        if (control(commands[i], pid, flags[i], NULL, 0) < 0 && !first)
            first = errno ? errno : EIO;
    }
    int rc = dirty(pid, 0);
    if (rc && !first) first = rc < 0 ? (errno ? errno : EIO) : rc;
    // Set and verify last: configuration calls must not silently undo priority.
    rc = TREnsurePriority(control, pid, darwinMajor, actual);
    return first ? first : rc;
}
#endif
