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

void *stringTransientAllocate(size_t size);
void *stringTransientReallocate(void *allocation, size_t size);

void compilerMetricsObserveStringConcat(size_t bytesCopied);
void compilerMetricsObserveStringSubstring(size_t sourceBytes, size_t resultBytes);
void compilerMetricsObserveConstructObject(size_t nameBytes);
void compilerMetricsObserveConstructField(size_t nameBytes);
void compilerMetricsObserveConstructLookupProbe(void);


int32_t commandLineArgumentCount(void) {
    return *_NSGetArgc() - 1;
}

char *commandLineArgument(int32_t index) {
    int32_t actual = index + 1;
    int argc = *_NSGetArgc();
    char **argv = *_NSGetArgv();
    if (actual < 0 || actual >= argc) {
        return "";
    }
    return argv[actual];
}

char *readFile(char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) {
        return "";
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return "";
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return "";
    }
    rewind(file);
    char *buffer = malloc((size_t)size + 1);
    if (!buffer) {
        fclose(file);
        return "";
    }
    size_t readCount = fread(buffer, 1, (size_t)size, file);
    buffer[readCount] = 0;
    fclose(file);
    return buffer;
}

int32_t writeFile(char *path, char *text) {
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
    size_t length = strlen(text);
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

int32_t runProcess(char *executable, char *argumentRecords) {
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

int32_t runProcessBatch(char *planRecords, int32_t maximumParallelism) {
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

int32_t stringLength(char *value) {
    if (!value) {
        return 0;
    }
    return (int32_t)strlen(value);
}

int32_t stringIndexOf(char *source, char *needle, int32_t start) {
    if (!source || !needle) {
        return 0;
    }
    int32_t length = (int32_t)strlen(source);
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

int32_t stringEqual(char *left, char *right) {
    if (!left || !right) {
        return left == right;
    }
    return strcmp(left, right) == 0;
}

int32_t stringCompare(char *left, char *right) {
    if (!left) {
        left = "";
    }
    if (!right) {
        right = "";
    }
    return (int32_t)strcmp(left, right);
}

char *stringConcat(char *left, char *right) {
    if (!left) {
        left = "";
    }
    if (!right) {
        right = "";
    }
    size_t leftLength = strlen(left);
    size_t rightLength = strlen(right);
    char *buffer = stringTransientAllocate(leftLength + rightLength + 1);
    if (!buffer) {
        return "";
    }
    compilerMetricsObserveStringConcat(leftLength + rightLength);
    memcpy(buffer, left, leftLength);
    memcpy(buffer + leftLength, right, rightLength);
    buffer[leftLength + rightLength] = 0;
    return buffer;
}

typedef struct RangeOwnedStringHeader {
    uint64_t magic;
    size_t length;
    size_t capacity;
} RangeOwnedStringHeader;

static const uint64_t rangeOwnedStringMagic = UINT64_C(0x52414E4745535452);

static size_t rangeOwnedStringCapacity(size_t required) {
    size_t capacity = 16;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2) {
            return required;
        }
        capacity *= 2;
    }
    return capacity;
}

char *stringOwnedCopy(char *source) {
    if (!source) {
        source = "";
    }
    size_t length = strlen(source);
    size_t capacity = rangeOwnedStringCapacity(length);
    if (capacity > SIZE_MAX - sizeof(RangeOwnedStringHeader) - 1) {
        abort();
    }
    RangeOwnedStringHeader *header = stringTransientAllocate(
        sizeof(RangeOwnedStringHeader) + capacity + 1
    );
    if (!header) {
        return "";
    }
    header->magic = rangeOwnedStringMagic;
    header->length = length;
    header->capacity = capacity;
    char *buffer = (char *)(header + 1);
    memcpy(buffer, source, length + 1);
    return buffer;
}

char *stringAppendOwned(char *left, char *right) {
    if (!left || !right) {
        abort();
    }
    RangeOwnedStringHeader *header = ((RangeOwnedStringHeader *)left) - 1;
    if (header->magic != rangeOwnedStringMagic || header->length > header->capacity) {
        abort();
    }

    size_t rightLength = strlen(right);
    if (rightLength > SIZE_MAX - header->length) {
        abort();
    }
    size_t required = header->length + rightLength;
    uintptr_t leftAddress = (uintptr_t)left;
    uintptr_t rightAddress = (uintptr_t)right;
    bool rightAliasesLeft = rightAddress >= leftAddress
        && rightAddress <= leftAddress + header->length;
    size_t rightOffset = rightAliasesLeft ? (size_t)(rightAddress - leftAddress) : 0;

    if (required > header->capacity) {
        size_t capacity = rangeOwnedStringCapacity(required);
        if (capacity > SIZE_MAX - sizeof(RangeOwnedStringHeader) - 1) {
            abort();
        }
        header = stringTransientReallocate(
            header,
            sizeof(RangeOwnedStringHeader) + capacity + 1
        );
        if (!header) {
            return "";
        }
        header->capacity = capacity;
        left = (char *)(header + 1);
        if (rightAliasesLeft) {
            right = left + rightOffset;
        }
    }

    compilerMetricsObserveStringConcat(rightLength);
    memmove(left + header->length, right, rightLength);
    header->length = required;
    left[required] = 0;
    return left;
}

char *stringFromInt(int32_t value) {
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%d", value);
    size_t length = strlen(buffer);
    char *copy = stringTransientAllocate(length + 1);
    if (!copy) {
        return "";
    }
    memcpy(copy, buffer, length + 1);
    return copy;
}

char *stringFromBool(bool value) {
    return value ? "true" : "false";
}

typedef struct RangeConstructField {
    char *name;
    char *ptrValue;
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

void *rangeConstructCreate(char *name) {
    RangeConstructObject *object = stringTransientAllocate(sizeof(RangeConstructObject));
    if (!object) {
        return NULL;
    }
    memset(object, 0, sizeof(RangeConstructObject));
    object->name = rangeConstructCopyText(name);
    if (object->name) compilerMetricsObserveConstructObject(name ? strlen(name) : 0);
    return object;
}

void *rangeConstructSetPtr(void *opaque, char *name, char *value) {
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructEnsureField(object, name);
    if (field) {
        field->kind = 0;
        field->ptrValue = value;
    }
    return opaque;
}

void *rangeConstructSetInt(void *opaque, char *name, int32_t value) {
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructEnsureField(object, name);
    if (field) {
        field->kind = 1;
        field->intValue = value;
    }
    return opaque;
}

void *rangeConstructSetBool(void *opaque, char *name, bool value) {
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructEnsureField(object, name);
    if (field) {
        field->kind = 2;
        field->boolValue = value;
    }
    return opaque;
}

char *rangeConstructGetPtr(void *opaque, char *name) {
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (!field || field->kind != 0 || !field->ptrValue) {
        return "";
    }
    return field->ptrValue;
}

int32_t rangeConstructGetInt(void *opaque, char *name) {
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (!field || field->kind != 1) {
        return 0;
    }
    return field->intValue;
}

bool rangeConstructGetBool(void *opaque, char *name) {
    RangeConstructObject *object = (RangeConstructObject *)opaque;
    RangeConstructField *field = rangeConstructLookupField(object, name);
    if (!field || field->kind != 2) {
        return false;
    }
    return field->boolValue;
}

char *stringCharacter(char *value, int32_t index) {
    if (!value || index < 0 || index >= (int32_t)strlen(value)) {
        return "";
    }
    char *buffer = stringTransientAllocate(2);
    if (!buffer) {
        return "";
    }
    buffer[0] = value[index];
    buffer[1] = 0;
    return buffer;
}

char *stringSubstring(char *value, int32_t start, int32_t end) {
    if (!value) {
        return "";
    }
    int32_t length = (int32_t)strlen(value);
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
    char *buffer = stringTransientAllocate(count + 1);
    if (!buffer) {
        return "";
    }
    compilerMetricsObserveStringSubstring((size_t)length, count);
    memcpy(buffer, value + start, count);
    buffer[count] = 0;
    return buffer;
}
