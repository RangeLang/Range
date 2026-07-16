#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <crt_externs.h>

void *stringTransientAllocate(size_t size);

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
