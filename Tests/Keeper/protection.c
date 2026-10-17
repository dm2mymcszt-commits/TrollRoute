#include "../../TrollRoute/Keeper/KeeperProtection.h"
#include <assert.h>
#include <stdio.h>

static int kernelMajor, effective, requested, reads, writes, calls;
static int failCommand, failRead, shortRead, wrongPID, ignoreSet, dirtyFailure;
static int commandOrder[32];
static int control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t size) {
    assert(pid == 42);
    commandOrder[calls++] = (int)command;
    if (command == 1) reads++;
    if ((int)command == failCommand || (command == 1 && reads == failRead)) {
        errno = EPERM; return -1;
    }
    if (command == 1) {
        assert(flags == 0 && size == sizeof(TRPriorityEntry));
        TRPriorityEntry *entry = buffer;
        entry->pid = wrongPID ? 43 : pid;
        entry->priority = effective;
        return shortRead ? 0 : (int)sizeof(*entry);
    }
    if (command == 2) {
        assert(flags == 0 && size == sizeof(TRPriorityRequest));
        writes++;
        requested = ((TRPriorityRequest *)buffer)->priority;
        if (!ignoreSet) {
            // Actual kernel behavior: silently coerce values in the aging range.
            int agingEnd = kernelMajor >= 22 ? 20 : 2;
            effective = requested > 0 && requested <= agingEnd ? 0 : requested;
        }
        return 0;
    }
    assert(buffer == NULL && size == 0);
    assert(command == 5 || command == 6 || command == 16 || command == 18);
    assert(flags == (command == 5 ? UINT32_MAX : 0));
    return 0;
}
static int dirty(int32_t pid, uint32_t flags) {
    assert(pid == 42 && flags == 0);
    commandOrder[calls++] = 100;
    // Exercise configuration undoing a priority: the verification must be last.
    effective = 0;
    return dirtyFailure;
}
static void reset(int major) {
    kernelMajor = major; effective = 0; requested = -1;
    reads = writes = calls = 0;
    failCommand = failRead = shortRead = wrongPID = ignoreSet = dirtyFailure = 0;
}
int main(void) {
    int32_t actual;
    reset(23);
    TRPriorityRequest legacy = {19, 0};
    assert(control(2, 42, 0, &legacy, sizeof(legacy)) == 0 && effective == 0);
    // The same legacy request cannot be mistaken for protection after readback.
    assert(TREnsurePriority(control, 42, 21, &actual) == EACCES && actual == 0);
    puts("PASS: successful legacy priority request on modern kernel is rejected");
    for (int major = 21; major <= 23; major++) {
        reset(major);
        assert(TRConfigureProtection(control, dirty, 42, major, &actual) == 0);
        assert(actual == (major == 21 ? 19 : 190) && requested == actual);
        assert(calls == 8 && commandOrder[4] == 100 && commandOrder[7] == 1);
        int before = writes;
        assert(TREnsurePriority(control, 42, major, &actual) == 0 && writes == before);
        effective = 0;
        assert(TREnsurePriority(control, 42, major, &actual) == 0 && writes == before + 1);
        assert(actual == (major == 21 ? 19 : 190));
    }
    puts("PASS: Darwin 21/22/23 configure, readback, idle checks and demotion repair");
    reset(23); ignoreSet = 1;
    assert(TRConfigureProtection(control, dirty, 42, 23, &actual) == EACCES && actual == 0);
    for (int read = 1; read <= 2; read++) {
        reset(23); failRead = read;
        assert(TRConfigureProtection(control, dirty, 42, 23, &actual) == EPERM && actual == -1);
    }
    reset(23); shortRead = 1;
    assert(TRConfigureProtection(control, dirty, 42, 23, &actual) == EIO && actual == -1);
    reset(23); wrongPID = 1;
    assert(TRConfigureProtection(control, dirty, 42, 23, &actual) == EIO && actual == -1);
    const int failures[] = {2, 5, 6, 16, 18};
    for (unsigned int i = 0; i < sizeof(failures) / sizeof(failures[0]); i++) {
        reset(23); failCommand = failures[i];
        assert(TRConfigureProtection(control, dirty, 42, 23, &actual) == EPERM);
    }
    reset(23); dirtyFailure = EBUSY;
    assert(TRConfigureProtection(control, dirty, 42, 23, &actual) == EBUSY);
    reset(23);
    assert(TRConfigureProtection(NULL, dirty, 42, 23, &actual) == ENOTSUP);
    assert(TRConfigureProtection(control, NULL, 42, 23, &actual) == ENOTSUP);
    assert(TRConfigureProtection(control, dirty, 42, 24, &actual) == ENOTSUP && calls == 0);
    assert(TRCriticalPriority(0) == -1 && TRCriticalPriority(20) == -1);
    puts("PASS: silent failure, query/ABI errors, configuration errors and unsupported kernels fail closed");
    return 0;
}
