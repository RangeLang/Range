#include <stddef.h>
#include <stdint.h>

void *rawBufferCreate(int32_t requestedCapacity, int32_t requestedStride);
int32_t rawBufferAppendRandomBytes(void *buffer, int32_t count);
int32_t rawBufferAppendUnsigned8(void *buffer, uint8_t value);
int32_t rawBufferCount(void *buffer);
uint8_t rawBufferLoadUnsigned8(void *buffer, int32_t index);
int32_t rawBufferStoreUnsigned8(void *buffer, int32_t index, uint8_t value);
int32_t rawBufferDestroy(void *buffer);

void *stringTransientAllocate(size_t size) {
    (void)size;
    return NULL;
}

void compilerMetricsObserveRawBufferAppend(size_t bytes) { (void)bytes; }
void compilerMetricsObserveRawBufferMaterialize(size_t bytes) { (void)bytes; }
void compilerMetricsObserveRawBufferReallocation(size_t bytes) { (void)bytes; }

int main(void) {
    void *values = rawBufferCreate(2, 1);
    if (!values) return 1;
    if (rawBufferAppendUnsigned8(values, 0) != 0) return 2;
    if (rawBufferAppendUnsigned8(values, UINT8_MAX) != 0) return 3;
    if (rawBufferLoadUnsigned8(values, 0) != 0) return 4;
    if (rawBufferLoadUnsigned8(values, 1) != UINT8_MAX) return 5;
    if (rawBufferStoreUnsigned8(values, 0, 127) != 0) return 6;
    if (rawBufferLoadUnsigned8(values, 0) != 127) return 7;
    if (rawBufferAppendRandomBytes(values, 16) != 0) return 8;
    if (rawBufferCount(values) != 18) return 9;
    if (rawBufferAppendRandomBytes(values, -1) == 0) return 10;
    if (rawBufferDestroy(values) != 0) return 11;
    return 0;
}
