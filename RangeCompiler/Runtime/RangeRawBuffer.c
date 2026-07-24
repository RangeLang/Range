#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *stringTransientAllocate(size_t size);
size_t stringTransientAllocationIndex(void *allocation);
void *stringTransientReallocateAt(void *allocation, size_t size, size_t allocationIndex);
void compilerMetricsObserveRawBufferAppend(size_t bytes);
void compilerMetricsObserveRawBufferMaterialize(size_t bytes);
void compilerMetricsObserveRawBufferReallocation(size_t bytesCopied);

typedef struct RangeRawBuffer {
    uint64_t magic;
    size_t count;
    size_t capacity;
    size_t stride;
    unsigned char *data;
    size_t transientDataIndex;
} RangeRawBuffer;

static const uint64_t rangeRawBufferOwnedMagic = UINT64_C(0x52414E4745425546);
static const uint64_t rangeRawBufferStaticMagic = UINT64_C(0x52414E4745425547);
static const uint64_t rangeRawBufferTransientMagic = UINT64_C(0x52414E4745425548);

static int rangeRawBufferHasMagic(const RangeRawBuffer *buffer) {
    return buffer
        && (buffer->magic == rangeRawBufferOwnedMagic
            || buffer->magic == rangeRawBufferStaticMagic
            || buffer->magic == rangeRawBufferTransientMagic);
}

char *rangeStringData(void *opaqueValue) {
    RangeRawBuffer *buffer = opaqueValue;
    if (rangeRawBufferHasMagic(buffer) && buffer->stride == 1 && buffer->data) {
        return (char *)buffer->data;
    }
    if (!opaqueValue) {
        return "";
    }
    abort();
}

size_t rangeStringSize(void *opaqueValue) {
    RangeRawBuffer *buffer = opaqueValue;
    if (rangeRawBufferHasMagic(buffer) && buffer->stride == 1 && buffer->data) {
        return buffer->count;
    }
    if (!opaqueValue) {
        return 0;
    }
    abort();
}

void *rangeStringCreateTransientCopy(const char *source, size_t count) {
    if (!source && count != 0) {
        return NULL;
    }
    RangeRawBuffer *buffer = stringTransientAllocate(sizeof(RangeRawBuffer));
    unsigned char *data = stringTransientAllocate(count + 1);
    if (!buffer || !data) {
        return NULL;
    }
    buffer->magic = rangeRawBufferTransientMagic;
    buffer->count = count;
    buffer->capacity = count;
    buffer->stride = 1;
    buffer->data = data;
    buffer->transientDataIndex = stringTransientAllocationIndex(data);
    if (count > 0) {
        memcpy(data, source, count);
    }
    data[count] = 0;
    return buffer;
}

void *rangeStringCreateTransientView(const char *source, size_t count) {
    if (!source && count != 0) {
        return NULL;
    }
    RangeRawBuffer *buffer = stringTransientAllocate(sizeof(RangeRawBuffer));
    if (!buffer) {
        return NULL;
    }
    buffer->magic = rangeRawBufferStaticMagic;
    buffer->count = count;
    buffer->capacity = count;
    buffer->stride = 1;
    buffer->data = (unsigned char *)(source ? source : "");
    buffer->transientDataIndex = SIZE_MAX;
    return buffer;
}

void *rangeStringEmpty(void) {
    static unsigned char emptyData[1] = {0};
    static RangeRawBuffer empty = {
        .magic = UINT64_C(0x52414E4745425547),
        .count = 0,
        .capacity = 0,
        .stride = 1,
        .data = emptyData,
        .transientDataIndex = SIZE_MAX
    };
    return &empty;
}

static int32_t rawBufferReserve(RangeRawBuffer *buffer, size_t additional) {
    if (!rangeRawBufferHasMagic(buffer) || !buffer->data || buffer->stride == 0
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

    unsigned char *data = NULL;
    if (buffer->magic == rangeRawBufferTransientMagic) {
        data = stringTransientReallocateAt(
            buffer->data,
            capacity * buffer->stride + 1,
            buffer->transientDataIndex
        );
    } else if (buffer->magic == rangeRawBufferStaticMagic) {
        data = malloc(capacity * buffer->stride + 1);
        if (data && buffer->count > 0) {
            memcpy(data, buffer->data, buffer->count * buffer->stride);
        }
        buffer->magic = rangeRawBufferOwnedMagic;
        buffer->transientDataIndex = SIZE_MAX;
    } else {
        data = realloc(buffer->data, capacity * buffer->stride + 1);
    }
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

    buffer->magic = rangeRawBufferOwnedMagic;
    buffer->capacity = capacity;
    buffer->stride = stride;
    buffer->data[0] = 0;
    buffer->transientDataIndex = SIZE_MAX;
    return buffer;
}

void *bufferCreateInt(int32_t requestedCapacity) {
    return rawBufferCreate(requestedCapacity, (int32_t)sizeof(int32_t));
}

void *bufferCreateUnsigned8(int32_t requestedCapacity) {
    return rawBufferCreate(requestedCapacity, (int32_t)sizeof(uint8_t));
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

int32_t rawBufferAppendText(void *opaqueBuffer, void *text) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1 || !text) {
        return -1;
    }

    char *textData = rangeStringData(text);
    size_t length = rangeStringSize(text);
    size_t oldCount = buffer->count;
    int32_t reserveResult = rawBufferReserve(buffer, length);
    if (reserveResult < 0) {
        return -1;
    }

    if (length > 0) {
        memcpy(buffer->data + buffer->count, textData, length);
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

int32_t rawBufferAppendTextCharacter(void *opaqueBuffer, void *source, int32_t index) {
    RangeRawBuffer *buffer = opaqueBuffer;
    char *sourceData = rangeStringData(source);
    size_t sourceCount = rangeStringSize(source);
    if (!buffer || buffer->stride != 1 || !source || index < 0 || (size_t)index >= sourceCount) {
        return -1;
    }

    size_t oldCount = buffer->count;
    int32_t reserveResult = rawBufferReserve(buffer, 1);
    if (reserveResult < 0) {
        return -1;
    }

    buffer->data[buffer->count] = (unsigned char)sourceData[index];
    buffer->count += 1;
    buffer->data[buffer->count] = 0;

    if (reserveResult > 0) {
        compilerMetricsObserveRawBufferReallocation(oldCount);
    }
    compilerMetricsObserveRawBufferAppend(1);
    return 0;
}

void *rawBufferMaterializeText(void *opaqueBuffer) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!buffer || buffer->stride != 1) {
        return rangeStringEmpty();
    }

    compilerMetricsObserveRawBufferMaterialize(buffer->count);
    void *text = rangeStringCreateTransientCopy((char *)buffer->data, buffer->count);
    if (!text) {
        abort();
    }
    return text;
}

int32_t rawBufferDestroy(void *opaqueBuffer) {
    RangeRawBuffer *buffer = opaqueBuffer;
    if (!rangeRawBufferHasMagic(buffer)) {
        return -1;
    }
    if (buffer->magic == rangeRawBufferStaticMagic
        || buffer->magic == rangeRawBufferTransientMagic) {
        return 0;
    }

    free(buffer->data);
    free(buffer);
    return 0;
}
