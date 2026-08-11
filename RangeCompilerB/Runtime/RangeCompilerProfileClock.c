#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#endif

const char *rangeStringData(void *value);
size_t rangeStringSize(void *value);
uint64_t rangeRawBufferLiveBytes(void);
uint64_t rangeRawBufferPeakBytes(void);
uint64_t rangeTransientLiveBytes(void);
uint64_t rangeTransientPeakBytes(void);
void rangeTransientPeakReset(void);
uint64_t rangeTransientPeakSinceReset(void);
void compilerMetricsObserveRawBufferAppendBase(size_t bytes);
void compilerMetricsObserveRawBufferMaterializeBase(size_t bytes);
void compilerMetricsObserveRawBufferReallocationBase(size_t bytes);
void compilerMetricsObserveStringConcatBase(size_t bytes);
void compilerMetricsObserveStringSubstringBase(size_t sourceBytes, size_t resultBytes);
void compilerMetricsObserveConstructObjectBase(size_t nameBytes);
void compilerMetricsObserveConstructFieldBase(size_t nameBytes);
void compilerMetricsObserveConstructLookupProbeBase(void);
void compilerMetricsObserveRawBufferLiveBytesBase(size_t liveBytes);
void compilerMetricsObserveTransientLiveBytesBase(size_t liveBytes);

int32_t compilerMetricsFunctionBeginBase(int32_t functionID, void *nameValue);
int32_t compilerMetricsFunctionEndBase(int32_t legacyParses, int32_t recordBytes);
int32_t compilerTelemetryProbeBeginBase(int32_t kind, int32_t functionID, int32_t instanceID, int32_t blockID, int32_t nodeID, int32_t ordinal, int32_t itemCount);
int32_t compilerTelemetryProbeEndBase(int32_t probeID, int32_t status, int32_t resultCount);

static bool traceActive;
static struct timespec traceStart;
static struct timespec functionStart;
static int32_t activeFunctionID;
static char *activeFunctionName;
static uint64_t reportedMaximumResidentBytes;
static uint64_t largestTransientWorkItemBytes;
static uint64_t transientWorkItemCount;
static uint64_t largestTransientFunctionBytes;
static uint64_t transientFunctionPeakCount;
static uint64_t activeFunctionTransientBaseline;
static uint64_t largestEmitterStageBytes;
static uint64_t emitterStageCount;
static uint64_t emitterStageBaselineBytes;
static uint64_t loweringStageBaselineBytes;
static uint64_t memoryStageBaselineBytes;

typedef struct RangeCompilerBufferSnapshot {
    struct timespec time;
    uint64_t appendCalls;
    uint64_t appendBytes;
    uint64_t materializeCalls;
    uint64_t materializeBytes;
    uint64_t reallocations;
    uint64_t reallocationBytes;
    uint64_t liveRawBufferBytes;
    uint64_t liveTransientBytes;
} RangeCompilerBufferSnapshot;

static RangeCompilerBufferSnapshot loweringStageBufferBaseline;
static RangeCompilerBufferSnapshot emitterStageBufferBaseline;
static uint64_t profileRawBufferAppendCalls;
static uint64_t profileRawBufferAppendBytes;
static uint64_t profileRawBufferMaterializeCalls;
static uint64_t profileRawBufferMaterializeBytes;
static uint64_t profileRawBufferReallocations;
static uint64_t profileRawBufferReallocationBytes;
static uint64_t profileStringConcatCalls;
static uint64_t profileStringConcatBytes;
static uint64_t profileStringSubstringCalls;
static uint64_t profileStringSubstringSourceBytes;
static uint64_t profileStringSubstringResultBytes;
static uint64_t profileConstructObjects;
static uint64_t profileConstructFields;
static uint64_t profileConstructNameBytes;
static uint64_t profileConstructLookupProbes;

typedef struct RangeCompilerProbeFrame {
    int32_t id;
    int32_t parentID;
    int32_t kind;
    int32_t functionID;
    int32_t instanceID;
    int32_t blockID;
    int32_t nodeID;
    int32_t ordinal;
    int32_t itemCount;
    RangeCompilerBufferSnapshot baseline;
    uint64_t stringConcatCalls;
    uint64_t stringConcatBytes;
    uint64_t stringSubstringCalls;
    uint64_t stringSubstringSourceBytes;
    uint64_t stringSubstringResultBytes;
    uint64_t constructObjects;
    uint64_t constructFields;
    uint64_t constructNameBytes;
    uint64_t constructLookupProbes;
    uint64_t currentResidentBytes;
    uint64_t maximumResidentBytes;
    uint64_t peakRawBufferBytes;
    uint64_t peakTransientBytes;
} RangeCompilerProbeFrame;

static RangeCompilerProbeFrame probeStack[64];
static size_t probeDepth;
static int32_t nextProbeID = 1;

static uint64_t elapsedMicroseconds(struct timespec start, struct timespec end);
static uint64_t elapsedNanoseconds(struct timespec start, struct timespec end);

static void observeProbeRawBufferLiveBytes(uint64_t liveBytes) {
    for (size_t index = 0; index < probeDepth; index += 1) {
        if (liveBytes > probeStack[index].peakRawBufferBytes) {
            probeStack[index].peakRawBufferBytes = liveBytes;
        }
    }
}

static void observeProbeTransientLiveBytes(uint64_t liveBytes) {
    for (size_t index = 0; index < probeDepth; index += 1) {
        if (liveBytes > probeStack[index].peakTransientBytes) {
            probeStack[index].peakTransientBytes = liveBytes;
        }
    }
}

void compilerMetricsObserveRawBufferAppend(size_t bytes) {
    profileRawBufferAppendCalls += 1;
    profileRawBufferAppendBytes += bytes;
    compilerMetricsObserveRawBufferAppendBase(bytes);
}

void compilerMetricsObserveRawBufferMaterialize(size_t bytes) {
    profileRawBufferMaterializeCalls += 1;
    profileRawBufferMaterializeBytes += bytes;
    compilerMetricsObserveRawBufferMaterializeBase(bytes);
}

void compilerMetricsObserveRawBufferReallocation(size_t bytes) {
    profileRawBufferReallocations += 1;
    profileRawBufferReallocationBytes += bytes;
    compilerMetricsObserveRawBufferReallocationBase(bytes);
}

void compilerMetricsObserveStringConcat(size_t bytes) {
    profileStringConcatCalls += 1;
    profileStringConcatBytes += bytes;
    compilerMetricsObserveStringConcatBase(bytes);
}

void compilerMetricsObserveStringSubstring(size_t sourceBytes, size_t resultBytes) {
    profileStringSubstringCalls += 1;
    profileStringSubstringSourceBytes += sourceBytes;
    profileStringSubstringResultBytes += resultBytes;
    compilerMetricsObserveStringSubstringBase(sourceBytes, resultBytes);
}

void compilerMetricsObserveConstructObject(size_t nameBytes) {
    profileConstructObjects += 1;
    profileConstructNameBytes += nameBytes;
    compilerMetricsObserveConstructObjectBase(nameBytes);
}

void compilerMetricsObserveConstructField(size_t nameBytes) {
    profileConstructFields += 1;
    profileConstructNameBytes += nameBytes;
    compilerMetricsObserveConstructFieldBase(nameBytes);
}

void compilerMetricsObserveConstructLookupProbe(void) {
    profileConstructLookupProbes += 1;
    compilerMetricsObserveConstructLookupProbeBase();
}

void compilerMetricsObserveRawBufferLiveBytes(size_t liveBytes) {
    observeProbeRawBufferLiveBytes((uint64_t)liveBytes);
    compilerMetricsObserveRawBufferLiveBytesBase(liveBytes);
}

void compilerMetricsObserveTransientLiveBytes(size_t liveBytes) {
    observeProbeTransientLiveBytes((uint64_t)liveBytes);
    compilerMetricsObserveTransientLiveBytesBase(liveBytes);
}

static RangeCompilerBufferSnapshot bufferSnapshot(void) {
    RangeCompilerBufferSnapshot snapshot = {
        .appendCalls = profileRawBufferAppendCalls,
        .appendBytes = profileRawBufferAppendBytes,
        .materializeCalls = profileRawBufferMaterializeCalls,
        .materializeBytes = profileRawBufferMaterializeBytes,
        .reallocations = profileRawBufferReallocations,
        .reallocationBytes = profileRawBufferReallocationBytes,
        .liveRawBufferBytes = rangeRawBufferLiveBytes(),
        .liveTransientBytes = rangeTransientLiveBytes()
    };
    clock_gettime(CLOCK_MONOTONIC, &snapshot.time);
    return snapshot;
}

static uint64_t counterDelta(uint64_t value, uint64_t baseline) {
    return value >= baseline ? value - baseline : 0;
}

static int64_t byteDelta(uint64_t value, uint64_t baseline) {
    return value >= baseline
        ? (int64_t)(value - baseline)
        : -(int64_t)(baseline - value);
}

static void reportBufferStage(
    const char *record,
    const char *name,
    RangeCompilerBufferSnapshot baseline
) {
    RangeCompilerBufferSnapshot current = bufferSnapshot();
    fprintf(stderr,
        "%s\tname=%s\tfunctionID=%d\tfunctionName=%s\tdurationMicroseconds=%llu"
        "\tappendCalls=%llu\tappendBytes=%llu"
        "\tmaterializeCalls=%llu\tmaterializeBytes=%llu"
        "\treallocations=%llu\treallocationBytes=%llu"
        "\tliveRawBufferDeltaBytes=%lld\tliveTransientDeltaBytes=%lld\n",
        record,
        name,
        traceActive ? activeFunctionID : -1,
        traceActive && activeFunctionName ? activeFunctionName : "entry",
        (unsigned long long)elapsedMicroseconds(baseline.time, current.time),
        (unsigned long long)counterDelta(current.appendCalls, baseline.appendCalls),
        (unsigned long long)counterDelta(current.appendBytes, baseline.appendBytes),
        (unsigned long long)counterDelta(current.materializeCalls, baseline.materializeCalls),
        (unsigned long long)counterDelta(current.materializeBytes, baseline.materializeBytes),
        (unsigned long long)counterDelta(current.reallocations, baseline.reallocations),
        (unsigned long long)counterDelta(current.reallocationBytes, baseline.reallocationBytes),
        (long long)byteDelta(current.liveRawBufferBytes, baseline.liveRawBufferBytes),
        (long long)byteDelta(current.liveTransientBytes, baseline.liveTransientBytes));
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

static uint64_t elapsedMicroseconds(struct timespec start, struct timespec end) {
    uint64_t seconds = end.tv_sec >= start.tv_sec ? (uint64_t)(end.tv_sec - start.tv_sec) : 0;
    int64_t nanoseconds = (int64_t)end.tv_nsec - (int64_t)start.tv_nsec;
    if (nanoseconds < 0 && seconds > 0) {
        seconds -= 1;
        nanoseconds += 1000000000;
    }
    return seconds * 1000000 + (uint64_t)(nanoseconds > 0 ? nanoseconds : 0) / 1000;
}

static uint64_t elapsedNanoseconds(struct timespec start, struct timespec end) {
    uint64_t seconds = end.tv_sec >= start.tv_sec ? (uint64_t)(end.tv_sec - start.tv_sec) : 0;
    int64_t nanoseconds = (int64_t)end.tv_nsec - (int64_t)start.tv_nsec;
    if (nanoseconds < 0 && seconds > 0) {
        seconds -= 1;
        nanoseconds += 1000000000;
    }
    return seconds * UINT64_C(1000000000) + (uint64_t)(nanoseconds > 0 ? nanoseconds : 0);
}

static uint64_t maximumResidentBytes(void) {
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) != 0) return 0;
#if defined(__APPLE__)
    return (uint64_t)usage.ru_maxrss;
#else
    return (uint64_t)usage.ru_maxrss * 1024;
#endif
}

static uint64_t currentResidentBytes(void) {
#if defined(__APPLE__)
    mach_task_basic_info_data_t information;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
            (task_info_t)&information, &count) != KERN_SUCCESS) {
        return 0;
    }
    return (uint64_t)information.resident_size;
#else
    return 0;
#endif
}

static const char *probeKindName(int32_t kind) {
    switch (kind) {
        case 1: return "ownedValidation";
        case 2: return "ownedValidation.descriptorCaches";
        case 3: return "ownedValidation.scheduleIndex";
        case 4: return "ownedValidation.predecessorIndex";
        case 5: return "ownedValidation.workspace";
        case 6: return "ownedValidation.blockSelection";
        case 7: return "ownedValidation.blockMerge";
        case 8: return "ownedValidation.blockEvaluation";
        case 9: return "ownedValidation.expiration";
        case 10: return "ownedValidation.terminal";
        case 11: return "ownedValidation.commit";
        case 12: return "ownedValidation.backedge";
        case 13: return "ownedValidation.terminalConsistency";
        case 14: return "ownedValidation.cleanup";
        case 15: return "ownedValidation.coalescingCheck";
        case 16: return "ownedValidation.referenceCheck";
        case 17: return "ownedValidation.applicationLookup";
        case 18: return "ownedValidation.constructMove";
        case 19: return "ownedValidation.runtimeContract";
        case 20: return "ownedValidation.instanceEffects";
        case 21: return "ownedValidation.returnTransfer";
        case 22: return "ownedValidation.optionalBranch";
        case 23: return "ownedValidation.localBinding";
        case 24: return "ownedValidation.assignment";
        case 25: return "ownedValidation.returnExit";
        default: return "unknown";
    }
}

int32_t compilerTelemetryProbeBegin(
    int32_t kind,
    int32_t functionID,
    int32_t instanceID,
    int32_t blockID,
    int32_t nodeID,
    int32_t ordinal,
    int32_t itemCount
) {
    int32_t baseStatus = compilerTelemetryProbeBeginBase(
        kind, functionID, instanceID, blockID, nodeID, ordinal, itemCount);
    if (baseStatus != 0 || probeDepth >= 64 || nextProbeID <= 0) return -1;
    RangeCompilerProbeFrame *frame = &probeStack[probeDepth];
    memset(frame, 0, sizeof(*frame));
    frame->id = nextProbeID++;
    frame->parentID = probeDepth > 0 ? probeStack[probeDepth - 1].id : 0;
    frame->kind = kind;
    frame->functionID = functionID;
    frame->instanceID = instanceID;
    frame->blockID = blockID;
    frame->nodeID = nodeID;
    frame->ordinal = ordinal;
    frame->itemCount = itemCount;
    frame->baseline = bufferSnapshot();
    frame->stringConcatCalls = profileStringConcatCalls;
    frame->stringConcatBytes = profileStringConcatBytes;
    frame->stringSubstringCalls = profileStringSubstringCalls;
    frame->stringSubstringSourceBytes = profileStringSubstringSourceBytes;
    frame->stringSubstringResultBytes = profileStringSubstringResultBytes;
    frame->constructObjects = profileConstructObjects;
    frame->constructFields = profileConstructFields;
    frame->constructNameBytes = profileConstructNameBytes;
    frame->constructLookupProbes = profileConstructLookupProbes;
    frame->currentResidentBytes = currentResidentBytes();
    frame->maximumResidentBytes = maximumResidentBytes();
    frame->peakRawBufferBytes = frame->baseline.liveRawBufferBytes;
    frame->peakTransientBytes = frame->baseline.liveTransientBytes;
    probeDepth += 1;
    fprintf(stderr,
        "compilerProbeBegin\tprobeID=%d\tparentID=%d\tdepth=%zu\tkind=%d\tname=%s"
        "\tfunctionID=%d\tinstanceID=%d\tblockID=%d\tnodeID=%d\tordinal=%d\titemCount=%d"
        "\ttotalNanoseconds=%llu\tcurrentResidentBytes=%llu\tmaximumResidentBytes=%llu"
        "\tliveRawBufferBytes=%llu\tpeakRawBufferBytes=%llu"
        "\tliveTransientBytes=%llu\tpeakTransientBytes=%llu\n",
        frame->id, frame->parentID, probeDepth - 1, kind, probeKindName(kind),
        functionID, instanceID, blockID, nodeID, ordinal, itemCount,
        (unsigned long long)(frame->baseline.time.tv_sec * UINT64_C(1000000000)
            + (uint64_t)frame->baseline.time.tv_nsec),
        (unsigned long long)frame->currentResidentBytes,
        (unsigned long long)frame->maximumResidentBytes,
        (unsigned long long)frame->baseline.liveRawBufferBytes,
        (unsigned long long)frame->peakRawBufferBytes,
        (unsigned long long)frame->baseline.liveTransientBytes,
        (unsigned long long)frame->peakTransientBytes);
    return frame->id;
}

int32_t compilerTelemetryProbeEnd(int32_t probeID, int32_t status, int32_t resultCount) {
    if (probeID == 0) return compilerTelemetryProbeEndBase(probeID, status, resultCount);
    if (probeDepth == 0 || probeStack[probeDepth - 1].id != probeID) return -1;
    RangeCompilerProbeFrame frame = probeStack[probeDepth - 1];
    RangeCompilerBufferSnapshot current = bufferSnapshot();
    uint64_t currentResident = currentResidentBytes();
    uint64_t maximumResident = maximumResidentBytes();
    probeDepth -= 1;
    fprintf(stderr,
        "compilerProbeEnd\tprobeID=%d\tparentID=%d\tdepth=%zu\tkind=%d\tname=%s"
        "\tfunctionID=%d\tinstanceID=%d\tblockID=%d\tnodeID=%d\tordinal=%d\titemCount=%d"
        "\tstatus=%d\tresultCount=%d\tdurationNanoseconds=%llu"
        "\tappendCalls=%llu\tappendBytes=%llu\tmaterializeCalls=%llu\tmaterializeBytes=%llu"
        "\treallocations=%llu\treallocationBytes=%llu"
        "\tstringConcatCalls=%llu\tstringConcatBytes=%llu"
        "\tstringSubstringCalls=%llu\tstringSubstringSourceBytes=%llu\tstringSubstringResultBytes=%llu"
        "\tconstructObjects=%llu\tconstructFields=%llu\tconstructNameBytes=%llu\tconstructLookupProbes=%llu"
        "\tstartResidentBytes=%llu\tendResidentBytes=%llu\tmaximumResidentBytes=%llu"
        "\tstartRawBufferBytes=%llu\tendRawBufferBytes=%llu\tlocalPeakRawBufferBytes=%llu\tlocalPeakRawBufferDeltaBytes=%llu"
        "\tstartTransientBytes=%llu\tendTransientBytes=%llu\tlocalPeakTransientBytes=%llu\tlocalPeakTransientDeltaBytes=%llu\n",
        frame.id, frame.parentID, probeDepth, frame.kind, probeKindName(frame.kind),
        frame.functionID, frame.instanceID, frame.blockID, frame.nodeID,
        frame.ordinal, frame.itemCount, status, resultCount,
        (unsigned long long)elapsedNanoseconds(frame.baseline.time, current.time),
        (unsigned long long)counterDelta(current.appendCalls, frame.baseline.appendCalls),
        (unsigned long long)counterDelta(current.appendBytes, frame.baseline.appendBytes),
        (unsigned long long)counterDelta(current.materializeCalls, frame.baseline.materializeCalls),
        (unsigned long long)counterDelta(current.materializeBytes, frame.baseline.materializeBytes),
        (unsigned long long)counterDelta(current.reallocations, frame.baseline.reallocations),
        (unsigned long long)counterDelta(current.reallocationBytes, frame.baseline.reallocationBytes),
        (unsigned long long)counterDelta(profileStringConcatCalls, frame.stringConcatCalls),
        (unsigned long long)counterDelta(profileStringConcatBytes, frame.stringConcatBytes),
        (unsigned long long)counterDelta(profileStringSubstringCalls, frame.stringSubstringCalls),
        (unsigned long long)counterDelta(profileStringSubstringSourceBytes, frame.stringSubstringSourceBytes),
        (unsigned long long)counterDelta(profileStringSubstringResultBytes, frame.stringSubstringResultBytes),
        (unsigned long long)counterDelta(profileConstructObjects, frame.constructObjects),
        (unsigned long long)counterDelta(profileConstructFields, frame.constructFields),
        (unsigned long long)counterDelta(profileConstructNameBytes, frame.constructNameBytes),
        (unsigned long long)counterDelta(profileConstructLookupProbes, frame.constructLookupProbes),
        (unsigned long long)frame.currentResidentBytes,
        (unsigned long long)currentResident,
        (unsigned long long)maximumResident,
        (unsigned long long)frame.baseline.liveRawBufferBytes,
        (unsigned long long)current.liveRawBufferBytes,
        (unsigned long long)frame.peakRawBufferBytes,
        (unsigned long long)counterDelta(frame.peakRawBufferBytes, frame.baseline.liveRawBufferBytes),
        (unsigned long long)frame.baseline.liveTransientBytes,
        (unsigned long long)current.liveTransientBytes,
        (unsigned long long)frame.peakTransientBytes,
        (unsigned long long)counterDelta(frame.peakTransientBytes, frame.baseline.liveTransientBytes));
    fflush(stderr);
    int32_t baseStatus = compilerTelemetryProbeEndBase(probeID, status, resultCount);
    return baseStatus == 0 ? 0 : baseStatus;
}

int32_t compilerMetricsFunctionBegin(int32_t functionID, void *nameValue) {
    int32_t baseStatus = compilerMetricsFunctionBeginBase(functionID, nameValue);
    if (baseStatus != 0) return baseStatus;
    if (functionID < 0) {
        const char *name = rangeStringData(nameValue);
        if (strcmp(name, "ownedReturnWorkItem.begin") == 0) {
            rangeTransientPeakReset();
        } else if (strncmp(name, "ownedReturnWorkItem.end.", 24) == 0) {
            uint64_t peakBytes = rangeTransientPeakSinceReset();
            transientWorkItemCount += 1;
            if (peakBytes > largestTransientWorkItemBytes) largestTransientWorkItemBytes = peakBytes;
            fprintf(stderr, "compilerTransientWorkItemPeak\tname=%s\tbytes=%llu\tcount=%llu\n",
                name,
                (unsigned long long)peakBytes,
                (unsigned long long)transientWorkItemCount);
        } else if (strncmp(name, "emitterStage.begin.", 19) == 0) {
            emitterStageBaselineBytes = rangeTransientPeakBytes();
            emitterStageBufferBaseline = bufferSnapshot();
        } else if (strncmp(name, "emitterStage.end.", 17) == 0) {
            uint64_t peakBytes = rangeTransientPeakBytes() >= emitterStageBaselineBytes
                ? rangeTransientPeakBytes() - emitterStageBaselineBytes : 0;
            emitterStageCount += 1;
            if (peakBytes > largestEmitterStageBytes) largestEmitterStageBytes = peakBytes;
            fprintf(stderr, "compilerEmitterStagePeak\tname=%s\tbytes=%llu\tcount=%llu\n",
                name,
                (unsigned long long)peakBytes,
                (unsigned long long)emitterStageCount);
            reportBufferStage("compilerEmitterStageBuffer", name, emitterStageBufferBaseline);
        } else if (strncmp(name, "loweringStage.begin.", 20) == 0) {
            loweringStageBaselineBytes = rangeTransientPeakBytes();
            loweringStageBufferBaseline = bufferSnapshot();
        } else if (strncmp(name, "loweringStage.end.", 18) == 0) {
            uint64_t peakBytes = rangeTransientPeakBytes() >= loweringStageBaselineBytes
                ? rangeTransientPeakBytes() - loweringStageBaselineBytes : 0;
            fprintf(stderr, "compilerLoweringStagePeak\tname=%s\tbytes=%llu\n",
                name, (unsigned long long)peakBytes);
            reportBufferStage("compilerLoweringStageBuffer", name, loweringStageBufferBaseline);
        } else if (strncmp(name, "memoryStage.begin.", 18) == 0) {
            memoryStageBaselineBytes = rangeTransientPeakBytes();
        } else if (strncmp(name, "memoryStage.end.", 16) == 0) {
            uint64_t peakBytes = rangeTransientPeakBytes() >= memoryStageBaselineBytes
                ? rangeTransientPeakBytes() - memoryStageBaselineBytes : 0;
            fprintf(stderr, "compilerMemoryStagePeak\tname=%s\tbytes=%llu\n",
                name, (unsigned long long)peakBytes);
        }
        fprintf(stderr, "compilerPhaseMemory\tname=%s\tcurrentResidentBytes=%llu\tmaximumResidentBytes=%llu\tliveRawBufferBytes=%llu\tpeakRawBufferBytes=%llu\tliveTransientBytes=%llu\tpeakTransientBytes=%llu\n",
            name,
            (unsigned long long)currentResidentBytes(),
            (unsigned long long)maximumResidentBytes(),
            (unsigned long long)rangeRawBufferLiveBytes(),
            (unsigned long long)rangeRawBufferPeakBytes(),
            (unsigned long long)rangeTransientLiveBytes(),
            (unsigned long long)rangeTransientPeakBytes());
        fflush(stderr);
        return 0;
    }
    if (traceActive || clock_gettime(CLOCK_MONOTONIC, &functionStart) != 0) return -1;
    if (traceStart.tv_sec == 0 && traceStart.tv_nsec == 0) traceStart = functionStart;
    size_t length = rangeStringSize(nameValue);
    activeFunctionName = malloc(length + 1);
    if (!activeFunctionName) return -1;
    memcpy(activeFunctionName, rangeStringData(nameValue), length);
    activeFunctionName[length] = 0;
    activeFunctionID = functionID;
    activeFunctionTransientBaseline = rangeTransientPeakBytes();
    traceActive = true;
    return 0;
}

int32_t compilerMetricsFunctionEnd(int32_t legacyParses, int32_t recordBytes) {
    if (!traceActive || !activeFunctionName) return -1;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    fprintf(stderr,
        "compilerFunctionEnd\tfunctionID=%d\tname=%s\tdurationMicroseconds=%llu\tdurationMilliseconds=%llu\ttotalMilliseconds=%llu\tlegacyParses=%d\trecordBytes=%d\n",
        activeFunctionID, activeFunctionName,
        (unsigned long long)elapsedMicroseconds(functionStart, now),
        (unsigned long long)elapsedMilliseconds(functionStart, now),
        (unsigned long long)elapsedMilliseconds(traceStart, now),
        legacyParses, recordBytes);
    uint64_t residentBytes = maximumResidentBytes();
    uint64_t transientPeak = rangeTransientPeakBytes();
    uint64_t transientDelta = transientPeak >= activeFunctionTransientBaseline
        ? transientPeak - activeFunctionTransientBaseline : 0;
    if (transientDelta > largestTransientFunctionBytes) {
        largestTransientFunctionBytes = transientDelta;
        transientFunctionPeakCount += 1;
        fprintf(stderr,
            "compilerFunctionTransientPeak\tfunctionID=%d\tname=%s\tbytes=%llu\tcount=%llu\n",
            activeFunctionID, activeFunctionName,
            (unsigned long long)transientDelta,
            (unsigned long long)transientFunctionPeakCount);
    }
    const uint64_t reportStepBytes = UINT64_C(64) * 1024 * 1024;
    if (residentBytes > reportedMaximumResidentBytes + reportStepBytes) {
        fprintf(stderr,
            "compilerFunctionMemoryPeak\tfunctionID=%d\tname=%s\tcurrentResidentBytes=%llu\tmaximumResidentBytes=%llu\n",
            activeFunctionID, activeFunctionName,
            (unsigned long long)currentResidentBytes(),
            (unsigned long long)residentBytes);
        reportedMaximumResidentBytes = residentBytes;
    }
    free(activeFunctionName);
    activeFunctionName = NULL;
    traceActive = false;
    fflush(stderr);
    return compilerMetricsFunctionEndBase(legacyParses, recordBytes);
}
