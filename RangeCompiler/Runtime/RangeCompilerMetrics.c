#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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
    uint64_t rawBufferAppendCalls;
    uint64_t rawBufferAppendBytes;
    uint64_t rawBufferMaterializeCalls;
    uint64_t rawBufferMaterializeBytes;
    uint64_t rawBufferReallocations;
    uint64_t rawBufferReallocationBytes;
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
    uint64_t rawBufferAppendCalls;
    uint64_t rawBufferAppendBytes;
    uint64_t rawBufferMaterializeCalls;
    uint64_t rawBufferMaterializeBytes;
    uint64_t rawBufferReallocations;
    uint64_t rawBufferReallocationBytes;
    RangeCompilerFunctionMetrics *functions;
    size_t functionCount;
    size_t functionCapacity;
    RangeCompilerFunctionMetrics *activeFunction;
    RangeCompilerFunctionMetrics baseline;
} RangeCompilerMetrics;

static RangeCompilerMetrics metrics;
static bool phaseTraceInitialized;
static struct timespec phaseTraceStart;
static struct timespec phaseTracePrior;

static void initializeTraceClock(void) {
    if (phaseTraceInitialized) return;
    if (clock_gettime(CLOCK_MONOTONIC, &phaseTraceStart) != 0) return;
    phaseTracePrior = phaseTraceStart;
    phaseTraceInitialized = true;
}

__attribute__((constructor))
static void initializeCompilerTrace(void) {
    const char *phaseEnabled = getenv("RANGE_COMPILER_PHASE_TRACE");
    const char *functionEnabled = getenv("RANGE_COMPILER_FUNCTION_TRACE");
    if ((phaseEnabled && strcmp(phaseEnabled, "1") == 0)
        || (functionEnabled && strcmp(functionEnabled, "1") == 0)) {
        initializeTraceClock();
    }
}

static uint64_t elapsedMilliseconds(struct timespec start, struct timespec end) {
    uint64_t seconds = end.tv_sec >= start.tv_sec ? (uint64_t)(end.tv_sec - start.tv_sec) : 0;
    int64_t nanoseconds = (int64_t)end.tv_nsec - (int64_t)start.tv_nsec;
    if (nanoseconds < 0 && seconds > 0) {
        seconds -= 1;
        nanoseconds += 1000000000;
    }
    return seconds * 1000 + (uint64_t)(nanoseconds > 0 ? nanoseconds : 0) / 1000000;
}

static int32_t tracePhase(char *name) {
    const char *enabled = getenv("RANGE_COMPILER_PHASE_TRACE");
    if (!enabled || strcmp(enabled, "1") != 0) return 0;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    if (!name) name = "";
    if (!phaseTraceInitialized) {
        initializeTraceClock();
        if (!phaseTraceInitialized) return -1;
        fprintf(stderr, "compilerPhase\tname=%s\telapsedMilliseconds=0\ttotalMilliseconds=0\n", name);
    } else {
        fprintf(stderr, "compilerPhase\tname=%s\telapsedMilliseconds=%llu\ttotalMilliseconds=%llu\n",
            name,
            (unsigned long long)elapsedMilliseconds(phaseTracePrior, now),
            (unsigned long long)elapsedMilliseconds(phaseTraceStart, now));
        phaseTracePrior = now;
    }
    fflush(stderr);
    return 0;
}

static int32_t traceFunction(int32_t functionID, char *name) {
    const char *enabled = getenv("RANGE_COMPILER_FUNCTION_TRACE");
    if (!enabled || strcmp(enabled, "1") != 0) return 0;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    if (!phaseTraceInitialized) {
        initializeTraceClock();
        if (!phaseTraceInitialized) return -1;
    }
    if (!name) name = "";
    fprintf(stderr, "compilerFunction\tfunctionID=%d\tname=%s\telapsedMilliseconds=%llu\ttotalMilliseconds=%llu\n",
        functionID, name,
        (unsigned long long)elapsedMilliseconds(phaseTracePrior, now),
        (unsigned long long)elapsedMilliseconds(phaseTraceStart, now));
    phaseTracePrior = now;
    fflush(stderr);
    return 0;
}

static void freeFunctions(void) {
    for (size_t index = 0; index < metrics.functionCount; index += 1) {
        free(metrics.functions[index].name);
    }
    free(metrics.functions);
}

int32_t compilerMetricsReset(void) {
    freeFunctions();
    memset(&metrics, 0, sizeof(metrics));
    phaseTraceInitialized = false;
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
    if (functionID < 0) return tracePhase(name);
    if (traceFunction(functionID, name) != 0) return -1;
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
    metrics.baseline.rawBufferAppendCalls = metrics.rawBufferAppendCalls;
    metrics.baseline.rawBufferAppendBytes = metrics.rawBufferAppendBytes;
    metrics.baseline.rawBufferMaterializeCalls = metrics.rawBufferMaterializeCalls;
    metrics.baseline.rawBufferMaterializeBytes = metrics.rawBufferMaterializeBytes;
    metrics.baseline.rawBufferReallocations = metrics.rawBufferReallocations;
    metrics.baseline.rawBufferReallocationBytes = metrics.rawBufferReallocationBytes;
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
    function->rawBufferAppendCalls = delta(metrics.rawBufferAppendCalls, metrics.baseline.rawBufferAppendCalls);
    function->rawBufferAppendBytes = delta(metrics.rawBufferAppendBytes, metrics.baseline.rawBufferAppendBytes);
    function->rawBufferMaterializeCalls = delta(metrics.rawBufferMaterializeCalls, metrics.baseline.rawBufferMaterializeCalls);
    function->rawBufferMaterializeBytes = delta(metrics.rawBufferMaterializeBytes, metrics.baseline.rawBufferMaterializeBytes);
    function->rawBufferReallocations = delta(metrics.rawBufferReallocations, metrics.baseline.rawBufferReallocations);
    function->rawBufferReallocationBytes = delta(metrics.rawBufferReallocationBytes, metrics.baseline.rawBufferReallocationBytes);
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

void compilerMetricsObserveRawBufferAppend(size_t bytes) {
    if (!metrics.enabled) return;
    metrics.rawBufferAppendCalls += 1;
    metrics.rawBufferAppendBytes += bytes;
}

void compilerMetricsObserveRawBufferMaterialize(size_t bytes) {
    if (!metrics.enabled) return;
    metrics.rawBufferMaterializeCalls += 1;
    metrics.rawBufferMaterializeBytes += bytes;
}

void compilerMetricsObserveRawBufferReallocation(size_t liveBytes) {
    if (!metrics.enabled) return;
    metrics.rawBufferReallocations += 1;
    metrics.rawBufferReallocationBytes += liveBytes;
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
        "\trawBufferAppendCalls=%llu\trawBufferAppendBytes=%llu"
        "\trawBufferMaterializeCalls=%llu\trawBufferMaterializeBytes=%llu"
        "\trawBufferReallocations=%llu\trawBufferReallocationBytes=%llu\n",
        metrics.enabled ? 1 : 0,
        (unsigned long long)metrics.stringConcatCalls, (unsigned long long)metrics.stringConcatBytes,
        (unsigned long long)metrics.stringSubstringCalls,
        (unsigned long long)metrics.stringSubstringSourceBytes,
        (unsigned long long)metrics.stringSubstringResultBytes,
        (unsigned long long)metrics.constructObjects, (unsigned long long)metrics.constructFields,
        (unsigned long long)metrics.constructNameBytes, (unsigned long long)metrics.constructLookupProbes,
        (unsigned long long)metrics.rawBufferAppendCalls, (unsigned long long)metrics.rawBufferAppendBytes,
        (unsigned long long)metrics.rawBufferMaterializeCalls,
        (unsigned long long)metrics.rawBufferMaterializeBytes,
        (unsigned long long)metrics.rawBufferReallocations,
        (unsigned long long)metrics.rawBufferReallocationBytes);
    for (size_t index = 0; index < metrics.functionCount && used < capacity; index += 1) {
        RangeCompilerFunctionMetrics *function = &metrics.functions[index];
        int written = snprintf(report + used, capacity - used,
            "compilerCostFunction\tfunctionID=%d\tname=%s\tlegacyParses=%llu\trecordBytes=%llu"
            "\tstringConcatCalls=%llu\tstringConcatBytes=%llu"
            "\tstringSubstringCalls=%llu\tstringSubstringSourceBytes=%llu\tstringSubstringResultBytes=%llu"
            "\trawBufferAppendCalls=%llu\trawBufferAppendBytes=%llu"
            "\trawBufferMaterializeCalls=%llu\trawBufferMaterializeBytes=%llu"
            "\trawBufferReallocations=%llu\trawBufferReallocationBytes=%llu\n",
            function->functionID, function->name,
            (unsigned long long)function->legacyParses, (unsigned long long)function->recordBytes,
            (unsigned long long)function->stringConcatCalls, (unsigned long long)function->stringConcatBytes,
            (unsigned long long)function->stringSubstringCalls,
            (unsigned long long)function->stringSubstringSourceBytes,
            (unsigned long long)function->stringSubstringResultBytes,
            (unsigned long long)function->rawBufferAppendCalls,
            (unsigned long long)function->rawBufferAppendBytes,
            (unsigned long long)function->rawBufferMaterializeCalls,
            (unsigned long long)function->rawBufferMaterializeBytes,
            (unsigned long long)function->rawBufferReallocations,
            (unsigned long long)function->rawBufferReallocationBytes);
        if (written < 0 || (size_t)written >= capacity - used) break;
        used += (size_t)written;
    }
    return report;
}
