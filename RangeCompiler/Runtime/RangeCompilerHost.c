#include <stdbool.h>
#include <errno.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <crt_externs.h>

extern char **environ;

char *rangeStringData(void *value);
size_t rangeStringSize(void *value);
void *rangeStringCreateTransientCopy(const char *source, size_t count);
void *rangeStringCreateTransientView(const char *source, size_t count);
void *rangeStringEmpty(void);
int32_t rawBufferAppendText(void *buffer, void *text);

static void **transientStringAllocations = NULL;
static size_t transientStringAllocationCount = 0;
static size_t transientStringAllocationCapacity = 0;
static int32_t transientStringRegionDepth = 0;

void *stringTransientAllocate(size_t size) {
    void *allocation = malloc(size);
    if (!allocation || transientStringRegionDepth == 0) {
        return allocation;
    }
    if (transientStringAllocationCount == transientStringAllocationCapacity) {
        size_t nextCapacity = transientStringAllocationCapacity == 0
            ? 1024
            : transientStringAllocationCapacity * 2;
        void **next = realloc(
            transientStringAllocations,
            nextCapacity * sizeof(void *)
        );
        if (!next) {
            abort();
        }
        transientStringAllocations = next;
        transientStringAllocationCapacity = nextCapacity;
    }
    transientStringAllocations[transientStringAllocationCount] = allocation;
    transientStringAllocationCount += 1;
    return allocation;
}

size_t stringTransientAllocationIndex(void *allocation) {
    if (!allocation || transientStringRegionDepth == 0) {
        return SIZE_MAX;
    }
    if (transientStringAllocationCount == 0
        || transientStringAllocations[transientStringAllocationCount - 1] != allocation) {
        abort();
    }
    return transientStringAllocationCount - 1;
}

void *stringTransientReallocateAt(
    void *allocation,
    size_t size,
    size_t allocationIndex
) {
    if (!allocation) {
        return stringTransientAllocate(size);
    }
    if (transientStringRegionDepth == 0 || allocationIndex == SIZE_MAX) {
        return realloc(allocation, size);
    }
    if (allocationIndex >= transientStringAllocationCount
        || transientStringAllocations[allocationIndex] != allocation) {
        abort();
    }
    void *next = realloc(allocation, size);
    if (!next) {
        return NULL;
    }
    transientStringAllocations[allocationIndex] = next;
    return next;
}

int32_t stringTransientRegionMark(void) {
    if (transientStringAllocationCount > INT32_MAX) {
        abort();
    }
    transientStringRegionDepth += 1;
    return (int32_t)transientStringAllocationCount;
}

int32_t stringTransientRegionReset(int32_t mark) {
    if (transientStringRegionDepth <= 0 || mark < 0
        || (size_t)mark > transientStringAllocationCount) {
        abort();
    }
    while (transientStringAllocationCount > (size_t)mark) {
        transientStringAllocationCount -= 1;
        free(transientStringAllocations[transientStringAllocationCount]);
    }
    transientStringRegionDepth -= 1;
    return 0;
}

int32_t stringPrint(void *value) {
    return puts(rangeStringData(value));
}

bool stringHasPrefix(void *opaqueSource, int32_t start, void *opaquePrefix) {
    char *source = rangeStringData(opaqueSource);
    char *prefix = rangeStringData(opaquePrefix);
    if (!source || !prefix || start < 0) {
        return false;
    }
    char *candidate = source + start;
    while (*prefix) {
        if (!*candidate || *candidate != *prefix) {
            return false;
        }
        candidate += 1;
        prefix += 1;
    }
    return true;
}

int32_t stringFindFrom(void *opaqueSource, int32_t start, void *opaqueNeedle) {
    char *source = rangeStringData(opaqueSource);
    char *needle = rangeStringData(opaqueNeedle);
    if (!source || !needle || start < 0) {
        return -1;
    }
    char *match = strstr(source + start, needle);
    if (!match) {
        return -1;
    }
    return (int32_t)(match - source);
}

int32_t stringFindFirstOf(void *opaqueSource, int32_t start, void *opaqueCharacters) {
    char *source = rangeStringData(opaqueSource);
    char *characters = rangeStringData(opaqueCharacters);
    if (!source || !characters || start < 0) {
        return -1;
    }
    char *match = strpbrk(source + start, characters);
    if (!match) {
        return -1;
    }
    return (int32_t)(match - source);
}

void *stringViewFrom(void *opaqueSource, int32_t start) {
    char *source = rangeStringData(opaqueSource);
    size_t sourceCount = rangeStringSize(opaqueSource);
    if (!source || start < 0 || (size_t)start > sourceCount) {
        return rangeStringEmpty();
    }
    return rangeStringCreateTransientView(source + start, sourceCount - (size_t)start);
}

void *stringCharacterAt(void *opaqueSource, int32_t index) {
    char *source = rangeStringData(opaqueSource);
    size_t sourceCount = rangeStringSize(opaqueSource);
    if (!source || index < 0 || (size_t)index >= sourceCount) {
        return rangeStringEmpty();
    }
    return rangeStringCreateTransientCopy(source + index, 1);
}

void *stringSliceUnchecked(void *opaqueSource, int32_t start, int32_t end) {
    char *source = rangeStringData(opaqueSource);
    size_t sourceCount = rangeStringSize(opaqueSource);
    if (!source || start < 0 || end < start || (size_t)end > sourceCount) {
        return rangeStringEmpty();
    }
    size_t count = (size_t)(end - start);
    return rangeStringCreateTransientCopy(source + start, count);
}

int32_t stringByteAt(void *opaqueSource, int32_t index) {
    char *source = rangeStringData(opaqueSource);
    if (!source || index < 0 || (size_t)index >= rangeStringSize(opaqueSource)) {
        return 0;
    }
    return (int32_t)(unsigned char)source[index];
}

int32_t stringFindByteOf(
    void *opaqueSource,
    int32_t start,
    int32_t first,
    int32_t second,
    int32_t third
) {
    char *source = rangeStringData(opaqueSource);
    if (!source || start < 0) {
        return -1;
    }
    size_t length = rangeStringSize(opaqueSource);
    if ((size_t)start >= length) {
        return -1;
    }
    unsigned char *cursor = (unsigned char *)source + start;
    while (*cursor) {
        int32_t value = (int32_t)*cursor;
        if (value == first || value == second || value == third) {
            return (int32_t)(cursor - (unsigned char *)source);
        }
        cursor += 1;
    }
    return -1;
}

void compilerMetricsObserveStringConcat(size_t bytesCopied);
void compilerMetricsObserveStringSubstring(size_t sourceBytes, size_t resultBytes);
void compilerMetricsObserveConstructObject(size_t nameBytes);
void compilerMetricsObserveConstructField(size_t nameBytes);
void compilerMetricsObserveConstructLookupProbe(void);


int32_t commandLineArgumentCount(void) {
    return *_NSGetArgc() - 1;
}

void *commandLineArgument(int32_t index) {
    int32_t actual = index + 1;
    int argc = *_NSGetArgc();
    char **argv = *_NSGetArgv();
    if (actual < 0 || actual >= argc) {
        return rangeStringEmpty();
    }
    return rangeStringCreateTransientCopy(argv[actual], strlen(argv[actual]));
}

void *readFile(void *opaquePath) {
    char *path = rangeStringData(opaquePath);
    FILE *file = fopen(path, "rb");
    if (!file) {
        return rangeStringEmpty();
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return rangeStringEmpty();
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return rangeStringEmpty();
    }
    rewind(file);
    char *buffer = malloc((size_t)size + 1);
    if (!buffer) {
        fclose(file);
        return rangeStringEmpty();
    }
    size_t readCount = fread(buffer, 1, (size_t)size, file);
    buffer[readCount] = 0;
    fclose(file);
    void *result = rangeStringCreateTransientCopy(buffer, readCount);
    free(buffer);
    return result ? result : rangeStringEmpty();
}

int32_t writeFile(void *opaquePath, void *opaqueText) {
    char *path = rangeStringData(opaquePath);
    char *text = rangeStringData(opaqueText);
    if (!path || !text) {
        return 73;
    }
    size_t pathLength = strlen(path);
    static const char temporarySuffix[] = ".tmp.XXXXXX";
    char *temporaryPath = malloc(pathLength + sizeof(temporarySuffix));
    if (!temporaryPath) {
        return 73;
    }
    snprintf(temporaryPath, pathLength + sizeof(temporarySuffix), "%s%s", path, temporarySuffix);
    int temporaryDescriptor = mkstemp(temporaryPath);
    if (temporaryDescriptor < 0) {
        free(temporaryPath);
        return 73;
    }
    FILE *file = fdopen(temporaryDescriptor, "wb");
    if (!file) {
        close(temporaryDescriptor);
        remove(temporaryPath);
        free(temporaryPath);
        return 73;
    }
    size_t length = rangeStringSize(opaqueText);
    size_t written = fwrite(text, 1, length, file);
    int closeStatus = fclose(file);
    if (written != length || closeStatus != 0) {
        remove(temporaryPath);
        free(temporaryPath);
        return 74;
    }
    if (rename(temporaryPath, path) != 0) {
        remove(temporaryPath);
        free(temporaryPath);
        return 73;
    }
    free(temporaryPath);
    return 0;
}

typedef struct {
    char **values;
    int32_t count;
} RangeProcessArguments;

static void rangeProcessArgumentsDestroy(RangeProcessArguments arguments) {
    for (int32_t index = 0; index < arguments.count; index += 1) {
        free(arguments.values[index]);
    }
    free(arguments.values);
}

static int32_t rangeProcessArgumentsDecode(char *records, RangeProcessArguments *result) {
    result->values = NULL;
    result->count = 0;
    if (!records) {
        return 64;
    }
    size_t cursor = 0;
    size_t recordsLength = strlen(records);
    int32_t capacity = 0;
    while (cursor < recordsLength) {
        if (records[cursor] < '0' || records[cursor] > '9') {
            rangeProcessArgumentsDestroy(*result);
            return 64;
        }
        size_t valueLength = 0;
        while (cursor < recordsLength && records[cursor] >= '0' && records[cursor] <= '9') {
            size_t digit = (size_t)(records[cursor] - '0');
            if (valueLength > (SIZE_MAX - digit) / 10) {
                rangeProcessArgumentsDestroy(*result);
                return 64;
            }
            valueLength = valueLength * 10 + digit;
            cursor += 1;
        }
        if (cursor >= recordsLength || records[cursor] != '\n' || valueLength > recordsLength - cursor - 1) {
            rangeProcessArgumentsDestroy(*result);
            return 64;
        }
        cursor += 1;
        if (result->count == capacity) {
            int32_t nextCapacity = capacity == 0 ? 8 : capacity * 2;
            char **nextValues = realloc(result->values, (size_t)nextCapacity * sizeof(char *));
            if (!nextValues) {
                rangeProcessArgumentsDestroy(*result);
                return 71;
            }
            result->values = nextValues;
            capacity = nextCapacity;
        }
        char *value = malloc(valueLength + 1);
        if (!value) {
            rangeProcessArgumentsDestroy(*result);
            return 71;
        }
        memcpy(value, records + cursor, valueLength);
        value[valueLength] = 0;
        result->values[result->count] = value;
        result->count += 1;
        cursor += valueLength;
    }
    return 0;
}

static int32_t rangeProcessWait(pid_t processID) {
    int status = 0;
    while (waitpid(processID, &status, 0) < 0) {
        if (errno != EINTR) {
            return 71;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 71;
}

static int32_t rangeProcessSpawn(char *executable, RangeProcessArguments arguments, pid_t *processID) {
    if (!executable || executable[0] == 0) {
        return 64;
    }
    char **argv = calloc((size_t)arguments.count + 2, sizeof(char *));
    if (!argv) {
        return 71;
    }
    argv[0] = executable;
    for (int32_t index = 0; index < arguments.count; index += 1) {
        argv[index + 1] = arguments.values[index];
    }
    int spawnStatus = posix_spawnp(processID, executable, NULL, NULL, argv, environ);
    free(argv);
    return spawnStatus == 0 ? 0 : 126;
}

int32_t runProcess(void *opaqueExecutable, void *opaqueArgumentRecords) {
    char *executable = rangeStringData(opaqueExecutable);
    char *argumentRecords = rangeStringData(opaqueArgumentRecords);
    RangeProcessArguments arguments;
    int32_t decodeStatus = rangeProcessArgumentsDecode(argumentRecords, &arguments);
    if (decodeStatus != 0) {
        return decodeStatus;
    }
    pid_t processID = 0;
    int32_t spawnStatus = rangeProcessSpawn(executable, arguments, &processID);
    if (spawnStatus != 0) {
        rangeProcessArgumentsDestroy(arguments);
        return spawnStatus;
    }
    int32_t exitStatus = rangeProcessWait(processID);
    rangeProcessArgumentsDestroy(arguments);
    return exitStatus;
}

int32_t runProcessBatch(void *opaquePlanRecords, int32_t maximumParallelism) {
    char *planRecords = rangeStringData(opaquePlanRecords);
    if (maximumParallelism <= 0 || maximumParallelism > 64) {
        return 64;
    }
    RangeProcessArguments plans;
    int32_t decodeStatus = rangeProcessArgumentsDecode(planRecords, &plans);
    if (decodeStatus != 0) {
        return decodeStatus;
    }
    pid_t *processIDs = calloc((size_t)maximumParallelism, sizeof(pid_t));
    int32_t *planIndexes = calloc((size_t)maximumParallelism, sizeof(int32_t));
    int32_t *statuses = calloc((size_t)plans.count, sizeof(int32_t));
    if (!processIDs || !planIndexes || (plans.count > 0 && !statuses)) {
        free(processIDs);
        free(planIndexes);
        free(statuses);
        rangeProcessArgumentsDestroy(plans);
        return 71;
    }
    int32_t nextPlan = 0;
    while (nextPlan < plans.count) {
        int32_t activeCount = 0;
        while (nextPlan < plans.count && activeCount < maximumParallelism) {
            RangeProcessArguments plan = { .values = NULL, .count = 0 };
            int32_t planStatus = rangeProcessArgumentsDecode(plans.values[nextPlan], &plan);
            if (planStatus == 0 && plan.count == 0) {
                planStatus = 64;
            }
            if (planStatus == 0) {
                RangeProcessArguments arguments = { .values = plan.values + 1, .count = plan.count - 1 };
                planStatus = rangeProcessSpawn(plan.values[0], arguments, &processIDs[activeCount]);
            }
            if (planStatus == 0) {
                planIndexes[activeCount] = nextPlan;
                activeCount += 1;
            } else {
                statuses[nextPlan] = planStatus;
            }
            if (plan.count > 0) {
                for (int32_t index = 0; index < plan.count; index += 1) {
                    free(plan.values[index]);
                }
                free(plan.values);
            }
            nextPlan += 1;
        }
        for (int32_t activeIndex = 0; activeIndex < activeCount; activeIndex += 1) {
            statuses[planIndexes[activeIndex]] = rangeProcessWait(processIDs[activeIndex]);
        }
    }
    int32_t result = 0;
    for (int32_t index = 0; index < plans.count; index += 1) {
        if (result == 0 && statuses[index] != 0) {
            result = statuses[index];
        }
    }
    free(processIDs);
    free(planIndexes);
    free(statuses);
    rangeProcessArgumentsDestroy(plans);
    return result;
}

int32_t stringLength(void *value) {
    size_t count = rangeStringSize(value);
    if (count > INT32_MAX) {
        abort();
    }
    return (int32_t)count;
}

int32_t stringIndexOf(void *opaqueSource, void *opaqueNeedle, int32_t start) {
    char *source = rangeStringData(opaqueSource);
    char *needle = rangeStringData(opaqueNeedle);
    if (!source || !needle) {
        return 0;
    }
    int32_t length = stringLength(opaqueSource);
    if (start < 0) {
        start = 0;
    }
    if (start > length) {
        return length;
    }
    char *match = strstr(source + start, needle);
    if (!match) {
        return length;
    }
    return (int32_t)(match - source);
}

int32_t stringEqual(void *opaqueLeft, void *opaqueRight) {
    char *left = rangeStringData(opaqueLeft);
    char *right = rangeStringData(opaqueRight);
    size_t leftCount = rangeStringSize(opaqueLeft);
    size_t rightCount = rangeStringSize(opaqueRight);
    if (leftCount != rightCount) {
        return 0;
    }
    return leftCount == 0 || memcmp(left, right, leftCount) == 0;
}

int32_t stringCompare(void *opaqueLeft, void *opaqueRight) {
    char *left = rangeStringData(opaqueLeft);
    char *right = rangeStringData(opaqueRight);
    size_t leftCount = rangeStringSize(opaqueLeft);
    size_t rightCount = rangeStringSize(opaqueRight);
    size_t sharedCount = leftCount < rightCount ? leftCount : rightCount;
    int compared = sharedCount > 0 ? memcmp(left, right, sharedCount) : 0;
    if (compared != 0) {
        return compared;
    }
    if (leftCount == rightCount) {
        return 0;
    }
    return leftCount < rightCount ? -1 : 1;
}

void *stringConcat(void *opaqueLeft, void *opaqueRight) {
    char *left = rangeStringData(opaqueLeft);
    char *right = rangeStringData(opaqueRight);
    size_t leftLength = rangeStringSize(opaqueLeft);
    size_t rightLength = rangeStringSize(opaqueRight);
    if (leftLength > SIZE_MAX - rightLength) {
        abort();
    }
    char *joined = stringTransientAllocate(leftLength + rightLength + 1);
    if (!joined) {
        return rangeStringEmpty();
    }
    compilerMetricsObserveStringConcat(leftLength + rightLength);
    memcpy(joined, left, leftLength);
    memcpy(joined + leftLength, right, rightLength);
    joined[leftLength + rightLength] = 0;
    return rangeStringCreateTransientCopy(joined, leftLength + rightLength);
}

void *stringOwnedCopy(void *source) {
    return rangeStringCreateTransientCopy(
        rangeStringData(source),
        rangeStringSize(source)
    );
}

void *stringAppendOwned(void *opaqueLeft, void *opaqueRight) {
    if (rawBufferAppendText(opaqueLeft, opaqueRight) != 0) {
        abort();
    }
    return opaqueLeft;
}

void *stringFromInt(int32_t value) {
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%d", value);
    size_t length = strlen(buffer);
    return rangeStringCreateTransientCopy(buffer, length);
}

void *stringFromBool(bool value) {
    return value
        ? rangeStringCreateTransientCopy("true", 4)
        : rangeStringCreateTransientCopy("false", 5);
}

typedef struct RangeConstructField {
    char *name;
    void *ptrValue;
    int32_t intValue;
    bool boolValue;
    int32_t kind;
    struct RangeConstructField *next;
} RangeConstructField;

typedef struct RangeConstructObject {
    char *name;
    RangeConstructField *fields;
} RangeConstructObject;

static char *rangeConstructCopyText(char *text) {
    if (!text) {
        text = "";
    }
    size_t length = strlen(text);
    char *copy = stringTransientAllocate(length + 1);
    if (!copy) {
        return NULL;
    }
    memcpy(copy, text, length + 1);
    return copy;
}

static RangeConstructField *rangeConstructLookupField(RangeConstructObject *object, char *name) {
    if (!object || !name) {
        return NULL;
    }
    RangeConstructField *field = object->fields;
    while (field) {
        compilerMetricsObserveConstructLookupProbe();
        if (strcmp(field->name, name) == 0) {
            return field;
        }
        field = field->next;
    }
    return NULL;
}

static RangeConstructField *rangeConstructEnsureField(RangeConstructObject *object, char *name) {
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (field || !object || !name) {
        return field;
    }
    field = stringTransientAllocate(sizeof(RangeConstructField));
    if (!field) {
        return NULL;
    }
    memset(field, 0, sizeof(RangeConstructField));
    field->name = rangeConstructCopyText(name);
    if (field->name) compilerMetricsObserveConstructField(strlen(name));
    field->next = object->fields;
    object->fields = field;
    return field;
}

void *rangeConstructCreate(void *opaqueName) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = stringTransientAllocate(sizeof(RangeConstructObject));
    if (!object) {
        return NULL;
    }
    memset(object, 0, sizeof(RangeConstructObject));
    object->name = rangeConstructCopyText(name);
    if (object->name) compilerMetricsObserveConstructObject(name ? strlen(name) : 0);
    return object;
}

void *rangeConstructSetPtr(void *opaque, void *opaqueName, void *value) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructEnsureField(object, name);
    if (field) {
        field->kind = 0;
        field->ptrValue = value;
    }
    return opaque;
}

void *rangeConstructSetInt(void *opaque, void *opaqueName, int32_t value) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructEnsureField(object, name);
    if (field) {
        field->kind = 1;
        field->intValue = value;
    }
    return opaque;
}

void *rangeConstructSetBool(void *opaque, void *opaqueName, bool value) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructEnsureField(object, name);
    if (field) {
        field->kind = 2;
        field->boolValue = value;
    }
    return opaque;
}

void *rangeConstructGetPtr(void *opaque, void *opaqueName) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (!field || field->kind != 0 || !field->ptrValue) {
        return rangeStringEmpty();
    }
    return field->ptrValue;
}

int32_t rangeConstructGetInt(void *opaque, void *opaqueName) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (!field || field->kind != 1) {
        return 0;
    }
    return field->intValue;
}

bool rangeConstructGetBool(void *opaque, void *opaqueName) {
    char *name = rangeStringData(opaqueName);
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (!field || field->kind != 2) {
        return false;
    }
    return field->boolValue;
}

void *stringCharacter(void *opaqueValue, int32_t index) {
    char *value = rangeStringData(opaqueValue);
    size_t valueCount = rangeStringSize(opaqueValue);
    if (!value || index < 0 || (size_t)index >= valueCount) {
        return rangeStringEmpty();
    }
    return rangeStringCreateTransientCopy(value + index, 1);
}

void *stringSubstring(void *opaqueValue, int32_t start, int32_t end) {
    char *value = rangeStringData(opaqueValue);
    int32_t length = stringLength(opaqueValue);
    if (start < 0) {
        start = 0;
    }
    if (end < start) {
        end = start;
    }
    if (end > length) {
        end = length;
    }
    size_t count = (size_t)(end - start);
    compilerMetricsObserveStringSubstring((size_t)length, count);
    return rangeStringCreateTransientCopy(value + start, count);
}
