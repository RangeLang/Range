#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *stringTransientAllocate(size_t size);

typedef struct RangeCompilerFunctionMetrics {
    int32_t functionID;
    char *name;
    uint64_t legacyParses;
    uint64_t recordBytes;
    uint64_t stringConcatCalls;
    uint64_t stringConcatBytes;
    uint64_t stringSubstringCalls;
    uint64_t stringSubstringSourceBytes;
    uint64_t stringSubstringResultBytes;
    uint64_t textBufferAppendCalls;
    uint64_t textBufferAppendBytes;
    uint64_t textBufferMaterializeCalls;
    uint64_t textBufferMaterializeBytes;
    uint64_t textBufferReallocations;
    uint64_t textBufferReallocationBytes;
} RangeCompilerFunctionMetrics;

typedef struct RangeCompilerMetrics {
    bool enabled;
    uint64_t stringConcatCalls;
    uint64_t stringConcatBytes;
    uint64_t stringSubstringCalls;
    uint64_t stringSubstringSourceBytes;
    uint64_t stringSubstringResultBytes;
    uint64_t constructObjects;
    uint64_t constructFields;
    uint64_t constructNameBytes;
    uint64_t constructLookupProbes;
    uint64_t textBufferAppendCalls;
    uint64_t textBufferAppendBytes;
    uint64_t textBufferMaterializeCalls;
    uint64_t textBufferMaterializeBytes;
    uint64_t textBufferReallocations;
    uint64_t textBufferReallocationBytes;
    RangeCompilerFunctionMetrics *functions;
    size_t functionCount;
    size_t functionCapacity;
    RangeCompilerFunctionMetrics *activeFunction;
    RangeCompilerFunctionMetrics baseline;
} RangeCompilerMetrics;

static RangeCompilerMetrics metrics;

static void freeFunctions(void) {
    for (size_t index = 0; index < metrics.functionCount; index += 1) {
        free(metrics.functions[index].name);
    }
    free(metrics.functions);
}

int32_t compilerMetricsReset(void) {
    freeFunctions();
    memset(&metrics, 0, sizeof(metrics));
    return 0;
}

int32_t compilerMetricsSetEnabled(bool enabled) {
    metrics.enabled = enabled;
    if (!enabled) metrics.activeFunction = NULL;
    return 0;
}

static uint64_t delta(uint64_t value, uint64_t baseline) {
    return value >= baseline ? value - baseline : 0;
}

int32_t compilerMetricsFunctionBegin(int32_t functionID, char *name) {
    if (!metrics.enabled || metrics.activeFunction) return metrics.enabled ? -1 : 0;
    if (metrics.functionCount == metrics.functionCapacity) {
        size_t capacity = metrics.functionCapacity > 0 ? metrics.functionCapacity * 2 : 64;
        RangeCompilerFunctionMetrics *functions = realloc(
            metrics.functions, capacity * sizeof(RangeCompilerFunctionMetrics));
        if (!functions) abort();
        metrics.functions = functions;
        metrics.functionCapacity = capacity;
    }
    RangeCompilerFunctionMetrics *function = &metrics.functions[metrics.functionCount++];
    memset(function, 0, sizeof(*function));
    function->functionID = functionID;
    if (!name) name = "";
    size_t length = strlen(name);
    function->name = malloc(length + 1);
    if (!function->name) abort();
    memcpy(function->name, name, length + 1);
    metrics.activeFunction = function;
    memset(&metrics.baseline, 0, sizeof(metrics.baseline));
    metrics.baseline.stringConcatCalls = metrics.stringConcatCalls;
    metrics.baseline.stringConcatBytes = metrics.stringConcatBytes;
    metrics.baseline.stringSubstringCalls = metrics.stringSubstringCalls;
    metrics.baseline.stringSubstringSourceBytes = metrics.stringSubstringSourceBytes;
    metrics.baseline.stringSubstringResultBytes = metrics.stringSubstringResultBytes;
    metrics.baseline.textBufferAppendCalls = metrics.textBufferAppendCalls;
    metrics.baseline.textBufferAppendBytes = metrics.textBufferAppendBytes;
    metrics.baseline.textBufferMaterializeCalls = metrics.textBufferMaterializeCalls;
    metrics.baseline.textBufferMaterializeBytes = metrics.textBufferMaterializeBytes;
    metrics.baseline.textBufferReallocations = metrics.textBufferReallocations;
    metrics.baseline.textBufferReallocationBytes = metrics.textBufferReallocationBytes;
    return 0;
}

int32_t compilerMetricsFunctionEnd(int32_t legacyParses, int32_t recordBytes) {
    RangeCompilerFunctionMetrics *function = metrics.activeFunction;
    if (!metrics.enabled || !function) return metrics.enabled ? -1 : 0;
    function->legacyParses = legacyParses > 0 ? (uint64_t)legacyParses : 0;
    function->recordBytes = recordBytes > 0 ? (uint64_t)recordBytes : 0;
    function->stringConcatCalls = delta(metrics.stringConcatCalls, metrics.baseline.stringConcatCalls);
    function->stringConcatBytes = delta(metrics.stringConcatBytes, metrics.baseline.stringConcatBytes);
    function->stringSubstringCalls = delta(metrics.stringSubstringCalls, metrics.baseline.stringSubstringCalls);
    function->stringSubstringSourceBytes = delta(metrics.stringSubstringSourceBytes, metrics.baseline.stringSubstringSourceBytes);
    function->stringSubstringResultBytes = delta(metrics.stringSubstringResultBytes, metrics.baseline.stringSubstringResultBytes);
    function->textBufferAppendCalls = delta(metrics.textBufferAppendCalls, metrics.baseline.textBufferAppendCalls);
    function->textBufferAppendBytes = delta(metrics.textBufferAppendBytes, metrics.baseline.textBufferAppendBytes);
    function->textBufferMaterializeCalls = delta(metrics.textBufferMaterializeCalls, metrics.baseline.textBufferMaterializeCalls);
    function->textBufferMaterializeBytes = delta(metrics.textBufferMaterializeBytes, metrics.baseline.textBufferMaterializeBytes);
    function->textBufferReallocations = delta(metrics.textBufferReallocations, metrics.baseline.textBufferReallocations);
    function->textBufferReallocationBytes = delta(metrics.textBufferReallocationBytes, metrics.baseline.textBufferReallocationBytes);
    metrics.activeFunction = NULL;
    return 0;
}

void compilerMetricsObserveStringConcat(size_t bytesCopied) {
    if (!metrics.enabled) return;
    metrics.stringConcatCalls += 1;
    metrics.stringConcatBytes += bytesCopied;
}

void compilerMetricsObserveStringSubstring(size_t sourceBytes, size_t resultBytes) {
    if (!metrics.enabled) return;
    metrics.stringSubstringCalls += 1;
    metrics.stringSubstringSourceBytes += sourceBytes;
    metrics.stringSubstringResultBytes += resultBytes;
}

void compilerMetricsObserveConstructObject(size_t nameBytes) {
    if (!metrics.enabled) return;
    metrics.constructObjects += 1;
    metrics.constructNameBytes += nameBytes;
}

void compilerMetricsObserveConstructField(size_t nameBytes) {
    if (!metrics.enabled) return;
    metrics.constructFields += 1;
    metrics.constructNameBytes += nameBytes;
}

void compilerMetricsObserveConstructLookupProbe(void) {
    if (metrics.enabled) metrics.constructLookupProbes += 1;
}

void compilerMetricsObserveTextBufferAppend(size_t bytes) {
    if (!metrics.enabled) return;
    metrics.textBufferAppendCalls += 1;
    metrics.textBufferAppendBytes += bytes;
}

void compilerMetricsObserveTextBufferMaterialize(size_t bytes) {
    if (!metrics.enabled) return;
    metrics.textBufferMaterializeCalls += 1;
    metrics.textBufferMaterializeBytes += bytes;
}

void compilerMetricsObserveTextBufferReallocation(size_t liveBytes) {
    if (!metrics.enabled) return;
    metrics.textBufferReallocations += 1;
    metrics.textBufferReallocationBytes += liveBytes;
}

char *compilerMetricsReport(void) {
    size_t capacity = 1024;
    for (size_t index = 0; index < metrics.functionCount; index += 1) {
        capacity += 640 + strlen(metrics.functions[index].name);
    }
    char *report = stringTransientAllocate(capacity);
    if (!report) return "";
    size_t used = (size_t)snprintf(report, capacity,
        "compilerCostMetrics\tenabled=%d\tstringConcatCalls=%llu\tstringConcatBytes=%llu"
        "\tstringSubstringCalls=%llu\tstringSubstringSourceBytes=%llu\tstringSubstringResultBytes=%llu"
        "\tconstructObjects=%llu\tconstructFields=%llu\tconstructNameBytes=%llu\tconstructGetProbes=%llu"
        "\ttextBufferAppendCalls=%llu\ttextBufferAppendBytes=%llu"
        "\ttextBufferMaterializeCalls=%llu\ttextBufferMaterializeBytes=%llu"
        "\ttextBufferReallocations=%llu\ttextBufferReallocationBytes=%llu\n",
        metrics.enabled ? 1 : 0,
        (unsigned long long)metrics.stringConcatCalls, (unsigned long long)metrics.stringConcatBytes,
        (unsigned long long)metrics.stringSubstringCalls,
        (unsigned long long)metrics.stringSubstringSourceBytes,
        (unsigned long long)metrics.stringSubstringResultBytes,
        (unsigned long long)metrics.constructObjects, (unsigned long long)metrics.constructFields,
        (unsigned long long)metrics.constructNameBytes, (unsigned long long)metrics.constructLookupProbes,
        (unsigned long long)metrics.textBufferAppendCalls, (unsigned long long)metrics.textBufferAppendBytes,
        (unsigned long long)metrics.textBufferMaterializeCalls,
        (unsigned long long)metrics.textBufferMaterializeBytes,
        (unsigned long long)metrics.textBufferReallocations,
        (unsigned long long)metrics.textBufferReallocationBytes);
    for (size_t index = 0; index < metrics.functionCount && used < capacity; index += 1) {
        RangeCompilerFunctionMetrics *function = &metrics.functions[index];
        int written = snprintf(report + used, capacity - used,
            "compilerCostFunction\tfunctionID=%d\tname=%s\tlegacyParses=%llu\trecordBytes=%llu"
            "\tstringConcatCalls=%llu\tstringConcatBytes=%llu"
            "\tstringSubstringCalls=%llu\tstringSubstringSourceBytes=%llu\tstringSubstringResultBytes=%llu"
            "\ttextBufferAppendCalls=%llu\ttextBufferAppendBytes=%llu"
            "\ttextBufferMaterializeCalls=%llu\ttextBufferMaterializeBytes=%llu"
            "\ttextBufferReallocations=%llu\ttextBufferReallocationBytes=%llu\n",
            function->functionID, function->name,
            (unsigned long long)function->legacyParses, (unsigned long long)function->recordBytes,
            (unsigned long long)function->stringConcatCalls, (unsigned long long)function->stringConcatBytes,
            (unsigned long long)function->stringSubstringCalls,
            (unsigned long long)function->stringSubstringSourceBytes,
            (unsigned long long)function->stringSubstringResultBytes,
            (unsigned long long)function->textBufferAppendCalls,
            (unsigned long long)function->textBufferAppendBytes,
            (unsigned long long)function->textBufferMaterializeCalls,
            (unsigned long long)function->textBufferMaterializeBytes,
            (unsigned long long)function->textBufferReallocations,
            (unsigned long long)function->textBufferReallocationBytes);
        if (written < 0 || (size_t)written >= capacity - used) break;
        used += (size_t)written;
    }
    return report;
}
