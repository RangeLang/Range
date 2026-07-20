#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *stringTransientAllocate(size_t size);
void compilerMetricsObserveRawBufferAppend(size_t bytes);
void compilerMetricsObserveRawBufferMaterialize(size_t bytes);
void compilerMetricsObserveRawBufferReallocation(size_t bytesCopied);

typedef struct RangeRawBuffer {
    size_t count;
    size_t capacity;
    size_t stride;
    unsigned char *data;
} RangeRawBuffer;

static int32_t rawBufferReserve(RangeRawBuffer *buffer, size_t additional) {
    if (!buffer || !buffer->data || buffer->stride == 0
        || buffer->count > buffer->capacity
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
    if (capacity > (SIZE_MAX - 1) / buffer->stride) {
        return -1;
    }

    unsigned char *data = realloc(buffer->data, capacity * buffer->stride + 1);
    if (!data) {
        abort();
    }

    buffer->data = data;
    buffer->capacity = capacity;
    return 1;
}

void *rawBufferCreate(int32_t requestedCapacity, int32_t requestedStride) {
    if (requestedCapacity < 0 || requestedStride <= 0) {
        return NULL;
    }

    size_t capacity = (size_t)requestedCapacity;
    size_t stride = (size_t)requestedStride;
    if (capacity > (SIZE_MAX - 1) / stride) {
        return NULL;
    }

    RangeRawBuffer *buffer = calloc(1, sizeof(RangeRawBuffer));
    if (!buffer) {
        abort();
    }

    buffer->data = malloc(capacity * stride + 1);
    if (!buffer->data) {
        abort();
    }

    buffer->capacity = capacity;
    buffer->stride = stride;
    buffer->data[0] = 0;
    return buffer;
}

int32_t rawBufferAppendInt(void *opaqueBuffer, int32_t value) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != sizeof(value) || buffer->count >= INT32_MAX) {
        return -1;
    }
    if (rawBufferReserve(buffer, 1) < 0) {
        return -1;
    }
    memcpy(buffer->data + buffer->count * buffer->stride, &value, sizeof(value));
    buffer->count += 1;
    return 0;
}

int32_t rawBufferAppendRandomBytes(void *opaqueBuffer, int32_t requestedCount) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1 || requestedCount < 0
        || (size_t)requestedCount > INT32_MAX - buffer->count) {
        return -1;
    }
    size_t count = (size_t)requestedCount;
    size_t oldCount = buffer->count;
    int32_t reserveResult = rawBufferReserve(buffer, count);
    if (reserveResult < 0) {
        return -1;
    }
    if (count > 0) {
        arc4random_buf(buffer->data + buffer->count, count);
        buffer->count += count;
    }
    buffer->data[buffer->count] = 0;
    if (reserveResult > 0) {
        compilerMetricsObserveRawBufferReallocation(oldCount);
    }
    compilerMetricsObserveRawBufferAppend(count);
    return 0;
}

int32_t rawBufferAppendUnsigned8(void *opaqueBuffer, uint8_t value) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1 || buffer->count >= INT32_MAX) {
        return -1;
    }
    size_t oldCount = buffer->count;
    int32_t reserveResult = rawBufferReserve(buffer, 1);
    if (reserveResult < 0) {
        return -1;
    }
    buffer->data[buffer->count] = value;
    buffer->count += 1;
    buffer->data[buffer->count] = 0;
    if (reserveResult > 0) {
        compilerMetricsObserveRawBufferReallocation(oldCount);
    }
    compilerMetricsObserveRawBufferAppend(1);
    return 0;
}

int32_t rawBufferCount(void *opaqueBuffer) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->count > INT32_MAX) {
        return -1;
    }
    return (int32_t)buffer->count;
}

int32_t rawBufferLoadInt(void *opaqueBuffer, int32_t index) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != sizeof(int32_t)
        || index < 0 || (size_t)index >= buffer->count) {
        abort();
    }

    int32_t value = 0;
    memcpy(&value, buffer->data + (size_t)index * buffer->stride, sizeof(value));
    return value;
}

uint8_t rawBufferLoadUnsigned8(void *opaqueBuffer, int32_t index) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1
        || index < 0 || (size_t)index >= buffer->count) {
        abort();
    }
    return buffer->data[index];
}

int32_t rawBufferStoreInt(void *opaqueBuffer, int32_t index, int32_t value) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != sizeof(value)
        || index < 0 || (size_t)index >= buffer->count) {
        return -1;
    }

    memcpy(buffer->data + (size_t)index * buffer->stride, &value, sizeof(value));
    return 0;
}

int32_t rawBufferStoreUnsigned8(void *opaqueBuffer, int32_t index, uint8_t value) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1
        || index < 0 || (size_t)index >= buffer->count) {
        return -1;
    }
    buffer->data[index] = value;
    return 0;
}

int32_t rawBufferAppendText(void *opaqueBuffer, char *text) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1 || !text) {
        return -1;
    }

    size_t length = strlen(text);
    size_t oldCount = buffer->count;
    int32_t reserveResult = rawBufferReserve(buffer, length);
    if (reserveResult < 0) {
        return -1;
    }

    if (length > 0) {
        memcpy(buffer->data + buffer->count, text, length);
        buffer->count += length;
    }
    buffer->data[buffer->count] = 0;

    if (reserveResult > 0) {
        compilerMetricsObserveRawBufferReallocation(oldCount);
    }
    compilerMetricsObserveRawBufferAppend(length);
    return 0;
}

int32_t rawBufferAppendTextInt(void *opaqueBuffer, int32_t value) {
    char text[32];
    int length = snprintf(text, sizeof(text), "%d", value);
    if (length < 0 || (size_t)length >= sizeof(text)) {
        return -1;
    }
    return rawBufferAppendText(opaqueBuffer, text);
}

int32_t rawBufferAppendTextCharacter(void *opaqueBuffer, char *source, int32_t index) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1 || !source || index < 0 || source[index] == 0) {
        return -1;
    }

    size_t oldCount = buffer->count;
    int32_t reserveResult = rawBufferReserve(buffer, 1);
    if (reserveResult < 0) {
        return -1;
    }

    buffer->data[buffer->count] = (unsigned char)source[index];
    buffer->count += 1;
    buffer->data[buffer->count] = 0;

    if (reserveResult > 0) {
        compilerMetricsObserveRawBufferReallocation(oldCount);
    }
    compilerMetricsObserveRawBufferAppend(1);
    return 0;
}

char *rawBufferMaterializeText(void *opaqueBuffer) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1) {
        return "";
    }

    compilerMetricsObserveRawBufferMaterialize(buffer->count);
    char *text = stringTransientAllocate(buffer->count + 1);
    if (!text) {
        abort();
    }

    memcpy(text, buffer->data, buffer->count + 1);
    return text;
}

int32_t rawBufferDestroy(void *opaqueBuffer) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer) {
        return -1;
    }

    free(buffer->data);
    free(buffer);
    return 0;
}
