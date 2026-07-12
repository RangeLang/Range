#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct RangeIntBuffer {
    size_t count;
    size_t capacity;
    int32_t *data;
} RangeIntBuffer;

static int32_t rangeIntBufferReserve(RangeIntBuffer *buffer, size_t additional) {
    if (!buffer || !buffer->data || buffer->count > buffer->capacity
        || buffer->count > SIZE_MAX - additional) {
        return -1;
    }

    size_t required = buffer->count + additional;
    if (required <= buffer->capacity) {
        return 0;
    }

    size_t capacity = buffer->capacity > 0 ? buffer->capacity : 16;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2) {
            capacity = required;
            break;
        }
        capacity *= 2;
    }
    if (capacity > SIZE_MAX / sizeof(int32_t)) {
        return -1;
    }

    int32_t *data = realloc(buffer->data, capacity * sizeof(int32_t));
    if (!data) {
        abort();
    }

    buffer->data = data;
    buffer->capacity = capacity;
    return 0;
}

void *intBufferCreate(int32_t requestedCapacity) {
    if (requestedCapacity < 0) {
        return NULL;
    }

    size_t capacity = requestedCapacity > 0 ? (size_t)requestedCapacity : 16;
    if (capacity > SIZE_MAX / sizeof(int32_t)) {
        return NULL;
    }

    RangeIntBuffer *buffer = calloc(1, sizeof(RangeIntBuffer));
    if (!buffer) {
        abort();
    }

    buffer->data = malloc(capacity * sizeof(int32_t));
    if (!buffer->data) {
        abort();
    }

    buffer->capacity = capacity;
    return buffer;
}

int32_t intBufferAppend(void *opaqueBuffer, int32_t value) {
    RangeIntBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->count >= INT32_MAX) {
        return -1;
    }
    if (rangeIntBufferReserve(buffer, 1) != 0) {
        return -1;
    }

    buffer->data[buffer->count] = value;
    buffer->count += 1;
    return 0;
}

int32_t intBufferCount(void *opaqueBuffer) {
    RangeIntBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->count > INT32_MAX) {
        return -1;
    }
    return (int32_t)buffer->count;
}

int32_t intBufferElement(void *opaqueBuffer, int32_t index) {
    RangeIntBuffer *buffer = opaqueBuffer;
    if (!buffer || index < 0 || (size_t)index >= buffer->count) {
        abort();
    }
    return buffer->data[index];
}

int32_t intBufferSet(void *opaqueBuffer, int32_t index, int32_t value) {
    RangeIntBuffer *buffer = opaqueBuffer;
    if (!buffer || index < 0 || (size_t)index >= buffer->count) {
        return -1;
    }
    buffer->data[index] = value;
    return 0;
}

int32_t intBufferDestroy(void *opaqueBuffer) {
    RangeIntBuffer *buffer = opaqueBuffer;
    if (!buffer) {
        return -1;
    }

    free(buffer->data);
    free(buffer);
    return 0;
}
