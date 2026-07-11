#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

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

bool stringHasPrefix(char *source, int32_t start, char *prefix) {
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

int32_t stringFindFrom(char *source, int32_t start, char *needle) {
    if (!source || !needle || start < 0) {
        return -1;
    }

    char *match = strstr(source + start, needle);
    if (!match) {
        return -1;
    }
    return (int32_t)(match - source);
}

int32_t stringFindFirstOf(char *source, int32_t start, char *characters) {
    if (!source || !characters || start < 0) {
        return -1;
    }

    char *match = strpbrk(source + start, characters);
    if (!match) {
        return -1;
    }
    return (int32_t)(match - source);
}

char *stringViewFrom(char *source, int32_t start) {
    if (!source || start < 0) {
        return "";
    }
    return source + start;
}

char *stringCharacterAt(char *source, int32_t index) {
    static char characters[256][2];
    if (!source || index < 0) {
        return "";
    }

    unsigned char character = (unsigned char)source[index];
    if (!character) {
        return "";
    }
    characters[character][0] = (char)character;
    return characters[character];
}

char *stringSliceUnchecked(char *source, int32_t start, int32_t end) {
    if (!source || start < 0 || end < start) {
        return "";
    }
    size_t count = (size_t)(end - start);
    char *slice = stringTransientAllocate(count + 1);
    if (!slice) {
        return "";
    }
    memcpy(slice, source + start, count);
    slice[count] = 0;
    return slice;
}

int32_t stringByteAt(char *source, int32_t index) {
    if (!source || index < 0) {
        return 0;
    }
    return (int32_t)(unsigned char)source[index];
}

int32_t stringFindByteOf(
    char *source,
    int32_t start,
    int32_t first,
    int32_t second,
    int32_t third
) {
    if (!source || start < 0) {
        return -1;
    }

    size_t length = strlen(source);
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
