#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct RangeTextBuffer {
    size_t count;
    size_t capacity;
    char *data;
} RangeTextBuffer;

static int32_t rangeTextBufferReserve(RangeTextBuffer *buffer, size_t additional) {
    if (!buffer || !buffer->data || buffer->count > buffer->capacity
        || buffer->count > SIZE_MAX - additional) {
        return -1;
    }

    size_t required = buffer->count + additional;
    if (required <= buffer->capacity) {
        return 0;
    }
    if (required == SIZE_MAX) {
        return -1;
    }

    size_t capacity = buffer->capacity > 0 ? buffer->capacity : 16;
    while (capacity < required) {
        if (capacity > (SIZE_MAX - 1) / 2) {
            capacity = required;
            break;
        }
        capacity *= 2;
    }

    char *data = realloc(buffer->data, capacity + 1);
    if (!data) {
        abort();
    }

    buffer->data = data;
    buffer->capacity = capacity;
    return 0;
}

void *textBufferCreate(int32_t requestedCapacity) {
    if (requestedCapacity < 0) {
        return NULL;
    }

    size_t capacity = requestedCapacity > 0 ? (size_t)requestedCapacity : 16;
    RangeTextBuffer *buffer = calloc(1, sizeof(RangeTextBuffer));
    if (!buffer) {
        abort();
    }

    buffer->data = malloc(capacity + 1);
    if (!buffer->data) {
        abort();
    }

    buffer->capacity = capacity;
    buffer->data[0] = 0;
    return buffer;
}

int32_t textBufferAppend(void *opaqueBuffer, char *text) {
    RangeTextBuffer *buffer = opaqueBuffer;
    if (!buffer || !text) {
        return -1;
    }

    size_t length = strlen(text);
    if (rangeTextBufferReserve(buffer, length) != 0) {
        return -1;
    }

    memcpy(buffer->data + buffer->count, text, length);
    buffer->count += length;
    buffer->data[buffer->count] = 0;
    return 0;
}

int32_t textBufferAppendInt(void *opaqueBuffer, int32_t value) {
    char text[32];
    int length = snprintf(text, sizeof(text), "%d", value);
    if (length < 0 || (size_t)length >= sizeof(text)) {
        return -1;
    }
    return textBufferAppend(opaqueBuffer, text);
}

int32_t textBufferAppendCharacter(void *opaqueBuffer, char *source, int32_t index) {
    RangeTextBuffer *buffer = opaqueBuffer;
    if (!buffer || !source || index < 0 || source[index] == 0) {
        return -1;
    }
    if (rangeTextBufferReserve(buffer, 1) != 0) {
        return -1;
    }

    buffer->data[buffer->count] = source[index];
    buffer->count += 1;
    buffer->data[buffer->count] = 0;
    return 0;
}

char *textBufferMaterialize(void *opaqueBuffer) {
    RangeTextBuffer *buffer = opaqueBuffer;
    if (!buffer || !buffer->data || buffer->count == SIZE_MAX) {
        return "";
    }

    char *text = malloc(buffer->count + 1);
    if (!text) {
        abort();
    }

    memcpy(text, buffer->data, buffer->count + 1);
    return text;
}

int32_t textBufferDestroy(void *opaqueBuffer) {
    RangeTextBuffer *buffer = opaqueBuffer;
    if (!buffer) {
        return -1;
    }

    free(buffer->data);
    free(buffer);
    return 0;
}
