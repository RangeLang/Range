#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

const char *rangeStringData(void *value);
size_t rangeStringSize(void *value);

int32_t compilerMetricsFunctionBeginBase(int32_t functionID, void *nameValue);
int32_t compilerMetricsFunctionEndBase(int32_t legacyParses, int32_t recordBytes);

static bool traceActive;
static struct timespec traceStart;
static struct timespec functionStart;
static int32_t activeFunctionID;
static char *activeFunctionName;

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

int32_t compilerMetricsFunctionBegin(int32_t functionID, void *nameValue) {
    int32_t baseStatus = compilerMetricsFunctionBeginBase(functionID, nameValue);
    if (baseStatus != 0 || functionID < 0) return baseStatus;
    if (traceActive || clock_gettime(CLOCK_MONOTONIC, &functionStart) != 0) return -1;
    if (traceStart.tv_sec == 0 && traceStart.tv_nsec == 0) traceStart = functionStart;
    size_t length = rangeStringSize(nameValue);
    activeFunctionName = malloc(length + 1);
    if (!activeFunctionName) return -1;
    memcpy(activeFunctionName, rangeStringData(nameValue), length);
    activeFunctionName[length] = 0;
    activeFunctionID = functionID;
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
    free(activeFunctionName);
    activeFunctionName = NULL;
    traceActive = false;
    fflush(stderr);
    return compilerMetricsFunctionEndBase(legacyParses, recordBytes);
}
