#include <stdbool.h>
#include <stdint.h>
#include <string.h>

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
