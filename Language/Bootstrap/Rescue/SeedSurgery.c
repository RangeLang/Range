#include <dlfcn.h>
#include <errno.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

static int rescueProjectModeAssembly(void) {
    return 1;
}

extern void rescueLowerEarlyReturnEntry(void);
void *rescueOriginalLowerEarlyReturnAddress = NULL;
void *rescueAppendExternLocalAddress = NULL;
void *rescueLocalRowAddress = NULL;
void *rescuePredicateCountAddress = NULL;
void *rescueAppendPredicateAddress = NULL;
void *rescueAppendReturnPathAddress = NULL;
struct RescueProjectRevision;
extern int32_t rescueInvokeAppendExternLocal(
    const struct RescueProjectRevision *project,
    const void *revision,
    int32_t ownerSyntaxID,
    int32_t localRow,
    const void *functions,
    void *operations,
    int32_t functionOrdinal,
    int32_t previousExecutionID
);
extern int32_t rescueInvokeLocalRow(
    const void *revision,
    int32_t ownerSyntaxID,
    int32_t expressionSyntaxID
);
extern int32_t rescueInvokePredicateCount(const void *revision, int32_t expressionSyntaxID);
extern int32_t rescueInvokeAppendPredicate(
    const void *revision,
    int32_t ownerSyntaxID,
    int32_t expressionSyntaxID,
    int32_t trueTargetExecutionID,
    int32_t falseTargetExecutionID,
    void *operations,
    int32_t functionOrdinal
);
extern int32_t rescueInvokeAppendReturnPath(
    const void *revision,
    int32_t returnRow,
    int32_t ownerSyntaxID,
    int32_t frameSize,
    void *operations,
    int32_t functionOrdinal
);

struct RescueExecutionCompassLowering {
    uint8_t found;
    uint8_t padding[3];
    int32_t errorCode;
};

struct RescueProjectRevision {
    uintptr_t fields[7];
};

typedef int32_t (*RescueManyCount)(void *storage);
typedef int32_t (*RescueManyElement)(void *storage, int32_t index);
typedef int32_t (*RescueManyUpdate)(void *storage, int32_t element, int32_t index);
typedef int32_t (*RescueManyAppend)(void *storage, int32_t element);

struct RescueMaskedOwner {
    void *owners;
    int32_t row;
    int32_t owner;
    int32_t kind;
    int32_t syntaxID;
};

struct RescueLoweringContext {
    void *result;
    void *callerReturnAddress;
    struct RescueProjectRevision project;
    const void *revision;
    int32_t ownerSyntaxID;
    const void *functions;
    void *operations;
    int32_t functionOrdinal;
    struct RescueMaskedOwner masked[64];
    int32_t maskedCount;
};

static struct RescueLoweringContext rescueContext;

static void *rescueProcessStore(const void *revision, int32_t ordinal) {
    void *process = *(void **)((const uint8_t *)revision + 12 * sizeof(uintptr_t));
    return ((void **)process)[ordinal];
}

static int rescueMaskOwner(
    void *owners,
    int32_t row,
    int32_t owner,
    int32_t kind,
    int32_t syntaxID,
    RescueManyUpdate update
) {
    if (rescueContext.maskedCount >= 64) {
        return 1;
    }
    if (update(owners, -2147483647, row) != 0) {
        return 2;
    }
    struct RescueMaskedOwner *masked =
        &rescueContext.masked[rescueContext.maskedCount++];
    masked->owners = owners;
    masked->row = row;
    masked->owner = owner;
    masked->kind = kind;
    masked->syntaxID = syntaxID;
    return 0;
}

static int rescueAppendOperation(
    void **operations,
    RescueManyAppend append,
    int32_t functionOrdinal,
    int32_t kind,
    int32_t target,
    int32_t operand,
    int32_t offset,
    int32_t width,
    int32_t syntaxID,
    int32_t ownerSyntaxID
) {
    const int32_t values[10] = {
        functionOrdinal, kind, target, operand, offset, width,
        syntaxID, ownerSyntaxID, 1, -1
    };
    for (int32_t field = 0; field < 10; ++field) {
        if (append(operations[field], values[field]) != 0) {
            return 1;
        }
    }
    return 0;
}

static int rescueAppendRelationship(
    void **operations,
    RescueManyAppend append,
    int32_t source,
    int32_t target,
    int32_t predicateValue,
    int32_t predicateExpectedValue
) {
    const int32_t values[5] = {
        source, target, 0, predicateValue, predicateExpectedValue
    };
    for (int32_t field = 0; field < 5; ++field) {
        if (append(operations[10 + field], values[field]) != 0) {
            return 1;
        }
    }
    return 0;
}

static int32_t rescueLocalOffset(
    void **locals,
    int32_t ownerSyntaxID,
    int32_t localRow,
    RescueManyElement element
) {
    int32_t offset = 0;
    for (int32_t row = 0; row < localRow; ++row) {
        if (element(locals[1], row) == ownerSyntaxID) {
            offset += 8;
        }
    }
    return offset;
}

static int32_t rescueAppendComparisonOperand(
    const void *revision,
    int32_t ownerSyntaxID,
    int32_t expressionSyntaxID,
    int32_t semanticValue,
    void **operations,
    int32_t functionOrdinal,
    RescueManyCount count,
    RescueManyElement element,
    RescueManyAppend append
) {
    void **expressions = (void **)rescueProcessStore(revision, 1);
    int32_t expressionRow = -1;
    for (int32_t row = 0; row < count(expressions[0]); ++row) {
        if (element(expressions[0], row) == expressionSyntaxID) {
            expressionRow = row;
            break;
        }
    }
    if (expressionRow < 0) {
        return -1;
    }
    const int32_t executionID = count(operations[1]);
    const int32_t kind = element(expressions[1], expressionRow);
    if (kind == 1 || kind == 2) {
        if (rescueAppendOperation(
                operations, append, functionOrdinal, 1, semanticValue,
                element(expressions[4], expressionRow), 0, 8,
                expressionSyntaxID, ownerSyntaxID
            ) != 0) {
            return -1;
        }
        return executionID;
    }
    if (rescueLocalRowAddress == NULL) {
        return -1;
    }
    const int32_t localRow = rescueInvokeLocalRow(
        revision, ownerSyntaxID, expressionSyntaxID);
    if (localRow < 0) {
        return -1;
    }
    void **locals = (void **)rescueProcessStore(revision, 6);
    if (rescueAppendOperation(
            operations, append, functionOrdinal, 5, semanticValue, -1,
            rescueLocalOffset(locals, ownerSyntaxID, localRow, element), 8,
            expressionSyntaxID, ownerSyntaxID
        ) != 0) {
        return -1;
    }
    return executionID;
}

static int32_t rescueAppendComparisonLocal(
    const void *revision,
    int32_t ownerSyntaxID,
    int32_t localRow,
    int32_t expressionSyntaxID,
    void **operations,
    int32_t functionOrdinal,
    int32_t previousExecutionID,
    RescueManyCount count,
    RescueManyElement element,
    RescueManyAppend append
) {
    void **comparisons = (void **)rescueProcessStore(revision, 13);
    int32_t comparisonRow = -1;
    for (int32_t row = 0; row < count(comparisons[0]); ++row) {
        if (element(comparisons[0], row) == expressionSyntaxID) {
            comparisonRow = row;
            break;
        }
    }
    if (comparisonRow < 0) {
        return -1;
    }
    const int32_t firstExecutionID = rescueAppendComparisonOperand(
        revision, ownerSyntaxID, element(comparisons[1], comparisonRow), 0,
        operations, functionOrdinal, count, element, append);
    const int32_t secondExecutionID = rescueAppendComparisonOperand(
        revision, ownerSyntaxID, element(comparisons[2], comparisonRow), 2,
        operations, functionOrdinal, count, element, append);
    if (firstExecutionID < 0 || secondExecutionID < 0) {
        return -1;
    }
    const int32_t compareExecutionID = count(operations[1]);
    const int32_t writeExecutionID = compareExecutionID + 1;
    void **locals = (void **)rescueProcessStore(revision, 6);
    if (rescueAppendOperation(
            operations, append, functionOrdinal, 13, 0, 2,
            element(comparisons[3], comparisonRow), 8,
            expressionSyntaxID, ownerSyntaxID
        ) != 0
        || rescueAppendOperation(
            operations, append, functionOrdinal, 4, -1, 3,
            rescueLocalOffset(locals, ownerSyntaxID, localRow, element), 8,
            element(locals[0], localRow), ownerSyntaxID
        ) != 0
        || (previousExecutionID >= 0 && rescueAppendRelationship(
            operations, append, previousExecutionID, firstExecutionID, -1, 0
        ) != 0)
        || rescueAppendRelationship(
            operations, append, firstExecutionID, secondExecutionID, -1, 0
        ) != 0
        || rescueAppendRelationship(
            operations, append, secondExecutionID, compareExecutionID, -1, 0
        ) != 0
        || rescueAppendRelationship(
            operations, append, compareExecutionID, writeExecutionID, -1, 0
        ) != 0) {
        return -1;
    }
    return writeExecutionID;
}

static int32_t rescueAppendStoredLocal(
    const void *revision,
    int32_t ownerSyntaxID,
    int32_t localRow,
    void **operations,
    int32_t functionOrdinal,
    int32_t previousExecutionID,
    RescueManyCount count,
    RescueManyElement element,
    RescueManyAppend append
) {
    void **locals = (void **)rescueProcessStore(revision, 6);
    void **expressions = (void **)rescueProcessStore(revision, 1);
    const int32_t sourceExpressionSyntaxID = element(locals[4], localRow);
    int32_t expressionSyntaxID = sourceExpressionSyntaxID;
    int32_t expressionRow = -1;
    const int32_t expressionCount = count(expressions[0]);
    for (int32_t row = 0; row < expressionCount; ++row) {
        if (element(expressions[0], row) == expressionSyntaxID) {
            expressionRow = row;
            break;
        }
    }
    if (expressionRow < 0) {
        return -1;
    }
    int32_t expressionKind = element(expressions[1], expressionRow);
    if (expressionKind != 1 && expressionKind != 2) {
        void **applications = (void **)rescueProcessStore(revision, 2);
        void **arguments = (void **)rescueProcessStore(revision, 3);
        int32_t applicationRow = -1;
        const int32_t applicationCount = count(applications[0]);
        for (int32_t row = 0; row < applicationCount; ++row) {
            if (element(applications[0], row) == expressionSyntaxID
                && element(applications[1], row) < 0) {
                applicationRow = row;
                break;
            }
        }
        int32_t nestedExpressionSyntaxID = -1;
        int32_t nestedCount = 0;
        if (applicationRow >= 0) {
            const int32_t argumentCount = count(arguments[0]);
            for (int32_t row = 0; row < argumentCount; ++row) {
                if (element(arguments[0], row) == expressionSyntaxID) {
                    nestedExpressionSyntaxID = element(arguments[2], row);
                    nestedCount += 1;
                }
            }
        }
        if (nestedCount == 1) {
            expressionSyntaxID = nestedExpressionSyntaxID;
            expressionRow = -1;
            for (int32_t row = 0; row < expressionCount; ++row) {
                if (element(expressions[0], row) == expressionSyntaxID) {
                    expressionRow = row;
                    break;
                }
            }
            if (expressionRow >= 0) {
                expressionKind = element(expressions[1], expressionRow);
            }
        }
    }
    if (expressionKind != 1 && expressionKind != 2) {
        if (expressionKind == 7) {
            return rescueAppendComparisonLocal(
                revision,
                ownerSyntaxID,
                localRow,
                expressionSyntaxID,
                operations,
                functionOrdinal,
                previousExecutionID,
                count,
                element,
                append
            );
        }
        return -1;
    }
    const int32_t offset = rescueLocalOffset(
        locals, ownerSyntaxID, localRow, element);
    const int32_t constantExecutionID = count(operations[1]);
    const int32_t writeExecutionID = constantExecutionID + 1;
    if (rescueAppendOperation(
            operations, append, functionOrdinal, 1, 2,
            element(expressions[4], expressionRow), 0, 8,
            sourceExpressionSyntaxID, ownerSyntaxID
        ) != 0
        || rescueAppendOperation(
            operations, append, functionOrdinal, 4, -1, 2, offset, 8,
            element(locals[0], localRow), ownerSyntaxID
        ) != 0
        || (previousExecutionID >= 0 && rescueAppendRelationship(
            operations, append, previousExecutionID, constantExecutionID, -1, 0
        ) != 0)
        || rescueAppendRelationship(
            operations, append, constantExecutionID, writeExecutionID, -1, 0
        ) != 0) {
        return -1;
    }
    return writeExecutionID;
}

static int32_t rescueAppendStoredReturn(
    const void *revision,
    int32_t ownerSyntaxID,
    void **operations,
    int32_t functionOrdinal,
    RescueManyCount count,
    RescueManyElement element,
    RescueManyUpdate update,
    RescueManyAppend append
) {
    void **returns = (void **)rescueProcessStore(revision, 8);
    void **locals = (void **)rescueProcessStore(revision, 6);
    int32_t returnRow = -1;
    int32_t returnSyntaxID = -1;
    for (int32_t row = 0; row < count(returns[0]); ++row) {
        const int32_t syntaxID = element(returns[0], row);
        if (element(returns[1], row) == ownerSyntaxID
            && syntaxID > returnSyntaxID) {
            returnRow = row;
            returnSyntaxID = syntaxID;
        }
    }
    if (returnRow < 0) {
        return -1;
    }
    const int32_t valueExpressionSyntaxID = element(returns[2], returnRow);
    if (rescueLocalRowAddress == NULL) {
        return -1;
    }
    const int32_t localRow = rescueInvokeLocalRow(
        revision, ownerSyntaxID, valueExpressionSyntaxID);
    if (localRow < 0) {
        return -1;
    }
    int32_t localOffset = 0;
    int32_t frameSize = 0;
    for (int32_t row = 0; row < count(locals[0]); ++row) {
        if (element(locals[1], row) != ownerSyntaxID) {
            continue;
        }
        if (row == localRow) {
            localOffset = frameSize;
        }
        frameSize += 8;
    }
    if ((frameSize & 15) != 0) {
        frameSize += 8;
    }
    const int32_t loadExecutionID = count(operations[1]);
    int32_t incoming = 0;
    for (int32_t row = 0; row < count(operations[10]); ++row) {
        if (element(operations[11], row) == loadExecutionID) {
            incoming += 1;
        }
    }
    if (incoming == 0
        || rescueAppendOperation(
            operations, append, functionOrdinal, 5, 0, -1, localOffset, 8,
            valueExpressionSyntaxID, ownerSyntaxID
        ) != 0
        || rescueAppendOperation(
            operations, append, functionOrdinal, 7, 0, 0, frameSize, 0,
            returnSyntaxID, ownerSyntaxID
        ) != 0
        || rescueAppendOperation(
            operations, append, functionOrdinal, 8, 0, 0, 0, 0,
            returnSyntaxID, ownerSyntaxID
        ) != 0
        || rescueAppendRelationship(
            operations, append, loadExecutionID, loadExecutionID + 1, -1, 0
        ) != 0
        || rescueAppendRelationship(
            operations, append, loadExecutionID + 1, loadExecutionID + 2, -1, 0
        ) != 0
        || update(operations[8], 3, loadExecutionID + 2) != 0) {
        return -1;
    }
    return loadExecutionID;
}

void rescueLowerEarlyReturn(
    struct RescueExecutionCompassLowering *result,
    const struct RescueProjectRevision *project,
    const void *revision,
    int32_t ownerSyntaxID,
    const void *functions,
    void *operations,
    int32_t functionOrdinal,
    void *callerReturnAddress
) {
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        static const char marker[] = "range seed surgery: helper entered\n";
        (void)write(STDERR_FILENO, marker, sizeof(marker) - 1);
    }
    (void)project;
    (void)functions;
    (void)operations;
    rescueContext.result = result;
    rescueContext.callerReturnAddress = callerReturnAddress;
    rescueContext.maskedCount = 0;
    rescueContext.project = *project;
    rescueContext.revision = revision;
    rescueContext.ownerSyntaxID = ownerSyntaxID;
    rescueContext.functions = functions;
    rescueContext.operations = operations;
    rescueContext.functionOrdinal = functionOrdinal;
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr,
            "range seed surgery: continuation entry result=%p revision=%p owner=%d function=%d\n",
            result, revision, ownerSyntaxID, functionOrdinal);
    }

    RescueManyCount count = (RescueManyCount)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__count");
    RescueManyElement element = (RescueManyElement)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__element");
    RescueManyUpdate update = (RescueManyUpdate)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__update");
    if (count == NULL || element == NULL || update == NULL) {
        result->found = 1;
        result->errorCode = 8;
        return;
    }

    void **conditionals = (void **)rescueProcessStore(revision, 10);
    void *conditionalSyntaxIDs = conditionals[0];
    void *conditionalOwners = conditionals[1];
    int32_t conditionalSyntaxID = -1;
    const int32_t conditionalCount = count(conditionalSyntaxIDs);
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr,
            "range seed surgery: conditionals=%p syntax=%p owners=%p count=%d\n",
            (void *)conditionals, conditionalSyntaxIDs, conditionalOwners,
            conditionalCount);
        fflush(stderr);
    }
    for (int32_t row = 0; row < conditionalCount; ++row) {
        if (element(conditionalOwners, row) == ownerSyntaxID) {
            conditionalSyntaxID = element(conditionalSyntaxIDs, row);
            break;
        }
    }

    void **returns = (void **)rescueProcessStore(revision, 8);
    void *returnSyntaxIDs = returns[0];
    void *returnOwners = returns[1];
    int32_t continuationSyntaxID = -1;
    const int32_t returnCount = count(returnSyntaxIDs);
    for (int32_t row = 0; row < returnCount; ++row) {
        if (element(returnOwners, row) == ownerSyntaxID) {
            continuationSyntaxID = element(returnSyntaxIDs, row);
            break;
        }
    }

    void **locals = (void **)rescueProcessStore(revision, 6);
    void *localSyntaxIDs = locals[0];
    void *localOwners = locals[1];
    const int32_t localCount = count(localSyntaxIDs);
    const char *maskSetting = getenv("RANGE_SEED_SURGERY_MASK");
    const int maskOwners = maskSetting == NULL || strcmp(maskSetting, "0") != 0;
    for (int32_t row = 0; row < localCount && maskOwners; ++row) {
        const int32_t owner = element(localOwners, row);
        const int32_t syntaxID = element(localSyntaxIDs, row);
        if (owner == ownerSyntaxID
            && syntaxID > conditionalSyntaxID
            && syntaxID < continuationSyntaxID
            && rescueMaskOwner(localOwners, row, owner, 0, syntaxID, update) != 0) {
            result->found = 1;
            result->errorCode = 8;
            return;
        }
    }
    for (int32_t row = 0; row < conditionalCount && maskOwners; ++row) {
        const int32_t owner = element(conditionalOwners, row);
        const int32_t syntaxID = element(conditionalSyntaxIDs, row);
        if (owner == ownerSyntaxID
            && syntaxID > conditionalSyntaxID
            && syntaxID < continuationSyntaxID
            && rescueMaskOwner(
                conditionalOwners, row, owner, 1, syntaxID, update
            ) != 0) {
            result->found = 1;
            result->errorCode = 8;
            return;
        }
    }
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr,
            "range seed surgery: continuation ABI owner=%d function=%d masked=%d\n",
            ownerSyntaxID, functionOrdinal, rescueContext.maskedCount);
        for (int32_t index = 0; index < rescueContext.maskedCount; ++index) {
            fprintf(stderr, "range seed surgery: masked kind=%d row=%d syntax=%d\n",
                rescueContext.masked[index].kind,
                rescueContext.masked[index].row,
                rescueContext.masked[index].syntaxID);
        }
        for (int32_t row = 0; row < conditionalCount; ++row) {
            fprintf(stderr, "range seed surgery: conditional row=%d syntax=%d owner=%d\n",
                row, element(conditionalSyntaxIDs, row),
                element(conditionalOwners, row));
        }
    }
}

void *rescueLowerEarlyReturnAfter(void) {
    struct RescueExecutionCompassLowering *result = rescueContext.result;
    RescueManyUpdate update = (RescueManyUpdate)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__update");
    RescueManyCount count = (RescueManyCount)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__count");
    RescueManyElement element = (RescueManyElement)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__element");
    RescueManyAppend append = (RescueManyAppend)dlsym(
        RTLD_DEFAULT, "CompilerBSeedIntManyTransport__append");
    if (update == NULL || count == NULL || element == NULL || append == NULL) {
        _Exit(70);
    }
    for (int32_t index = rescueContext.maskedCount - 1; index >= 0; --index) {
        struct RescueMaskedOwner *masked = &rescueContext.masked[index];
        if (update(masked->owners, masked->owner, masked->row) != 0) {
            _Exit(70);
        }
    }
    if (result->found && result->errorCode == 8
        && rescueContext.maskedCount > 0) {
        const int32_t returnStart = rescueAppendStoredReturn(
            rescueContext.revision,
            rescueContext.ownerSyntaxID,
            (void **)rescueContext.operations,
            rescueContext.functionOrdinal,
            count,
            element,
            update,
            append
        );
        if (returnStart >= 0) {
            result->errorCode = 0;
            if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
                fprintf(stderr,
                    "range seed surgery: materialized stored return start=%d\n",
                    returnStart);
            }
        }
    }
    if (!result->found || result->errorCode != 0) {
        if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
            void **operations = (void **)rescueContext.operations;
            fprintf(stderr,
                "range seed surgery: original continuation stopped found=%d error=%d masked=%d operations=%d relationships=%d\n",
                result->found, result->errorCode, rescueContext.maskedCount,
                count(operations[1]), count(operations[10]));
        }
        return rescueContext.callerReturnAddress;
    }
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr, "range seed surgery: original continuation completed masked=%d\n",
            rescueContext.maskedCount);
    }

    void **operations = (void **)rescueContext.operations;
    void *operationKinds = operations[1];
    void *nextTargets = operations[11];
    void *nextPredicateValues = operations[13];
    const int32_t oldContinuationReturnID = count(operationKinds) - 3;
    void **conditionals = (void **)rescueProcessStore(rescueContext.revision, 10);
    void **returns = (void **)rescueProcessStore(rescueContext.revision, 8);
    void **locals = (void **)rescueProcessStore(rescueContext.revision, 6);
    int32_t frameSize = 0;
    const int32_t localCount = count(locals[0]);
    for (int32_t row = 0; row < localCount; ++row) {
        if (element(locals[1], row) == rescueContext.ownerSyntaxID) {
            frameSize += 8;
        }
    }
    if ((frameSize & 15) != 0) {
        frameSize += 8;
    }
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr, "range seed surgery: restored locals=%d frame=%d operations=%d\n",
            localCount, frameSize, count(operationKinds));
    }

    int32_t previousSyntaxID = -1;
    int32_t tailRelationshipRow = -1;
    for (;;) {
        int32_t maskedIndex = -1;
        int32_t nextSyntaxID = INT32_MAX;
        for (int32_t index = 0; index < rescueContext.maskedCount; ++index) {
            struct RescueMaskedOwner *masked = &rescueContext.masked[index];
            if (masked->syntaxID > previousSyntaxID
                && masked->syntaxID < nextSyntaxID) {
                maskedIndex = index;
                nextSyntaxID = masked->syntaxID;
            }
        }
        if (maskedIndex < 0) {
            break;
        }
        struct RescueMaskedOwner *masked = &rescueContext.masked[maskedIndex];
        if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
            fprintf(stderr, "range seed surgery: effect kind=%d row=%d syntax=%d\n",
                masked->kind, masked->row, masked->syntaxID);
        }
        const int32_t effectStart = count(operationKinds);
        const int32_t relationshipCountBefore = count(operations[10]);
        int32_t lastExecutionID = -1;
        int32_t localTailRelationshipRow = -1;
        if (masked->kind == 0) {
            lastExecutionID = rescueAppendStoredLocal(
                rescueContext.revision,
                rescueContext.ownerSyntaxID,
                masked->row,
                operations,
                rescueContext.functionOrdinal,
                -1,
                count,
                element,
                append
            );
            if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
                fprintf(stderr,
                    "range seed surgery: local syntax=%d storedResult=%d operations=%d relationships=%d\n",
                    masked->syntaxID, lastExecutionID, count(operationKinds),
                    count(operations[10]));
            }
            if (lastExecutionID >= 0) {
                localTailRelationshipRow = count(operations[10]);
                if (rescueAppendRelationship(
                    operations, append, lastExecutionID,
                    oldContinuationReturnID, -1, 0
                ) != 0) {
                    result->errorCode = 8;
                    break;
                }
            } else if (count(operationKinds) == effectStart
                && count(operations[10]) == relationshipCountBefore) {
                lastExecutionID = rescueInvokeAppendExternLocal(
                    &rescueContext.project,
                    rescueContext.revision,
                    rescueContext.ownerSyntaxID,
                    masked->row,
                    rescueContext.functions,
                    rescueContext.operations,
                    rescueContext.functionOrdinal,
                    oldContinuationReturnID
                );
                if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
                    fprintf(stderr,
                        "range seed surgery: local syntax=%d externResult=%d operations=%d relationships=%d\n",
                        masked->syntaxID, lastExecutionID, count(operationKinds),
                        count(operations[10]));
                }
                if (lastExecutionID >= 0) {
                    localTailRelationshipRow = relationshipCountBefore;
                    if (update(operations[10], lastExecutionID,
                            localTailRelationshipRow) != 0
                        || update(nextTargets, oldContinuationReturnID,
                            localTailRelationshipRow) != 0) {
                        result->errorCode = 8;
                        break;
                    }
                }
            }
            if (lastExecutionID < 0) {
                result->errorCode = 6;
                break;
            }
        } else {
            const int32_t expressionSyntaxID = element(conditionals[4], masked->row);
            const int32_t bodySyntaxID = element(conditionals[5], masked->row);
            int32_t returnRow = -1;
            int32_t returnSyntaxID = INT32_MAX;
            const int32_t returnCount = count(returns[0]);
            for (int32_t row = 0; row < returnCount; ++row) {
                const int32_t syntaxID = element(returns[0], row);
                if (element(returns[1], row) == bodySyntaxID
                    && syntaxID < returnSyntaxID) {
                    returnRow = row;
                    returnSyntaxID = syntaxID;
                }
            }
            const int32_t predicateCount = rescueInvokePredicateCount(
                rescueContext.revision, expressionSyntaxID
            );
            const int32_t returnStart = effectStart + predicateCount;
            if (returnRow < 0 || predicateCount < 0
                || rescueInvokeAppendPredicate(
                    rescueContext.revision,
                    rescueContext.ownerSyntaxID,
                    expressionSyntaxID,
                    returnStart,
                    oldContinuationReturnID,
                    rescueContext.operations,
                    rescueContext.functionOrdinal
                ) != effectStart
                || rescueInvokeAppendReturnPath(
                    rescueContext.revision,
                    returnRow,
                    bodySyntaxID,
                    frameSize,
                    rescueContext.operations,
                    rescueContext.functionOrdinal
                ) != returnStart) {
                result->errorCode = 6;
                break;
            }
        }

        if (tailRelationshipRow >= 0) {
            if (update(nextTargets, effectStart, tailRelationshipRow) != 0) {
                result->errorCode = 8;
                break;
            }
        } else {
            int32_t rewiredCount = 0;
            for (int32_t row = 0; row < relationshipCountBefore; ++row) {
                if (element(nextTargets, row) == oldContinuationReturnID
                    && element(nextPredicateValues, row) >= 0) {
                    if (update(nextTargets, effectStart, row) != 0) {
                        result->errorCode = 8;
                        break;
                    }
                    rewiredCount += 1;
                }
            }
            if (result->errorCode != 0 || rewiredCount == 0) {
                result->errorCode = 8;
                break;
            }
        }
        tailRelationshipRow = masked->kind == 0
            ? localTailRelationshipRow : -1;
        previousSyntaxID = nextSyntaxID;
    }
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr, "range seed surgery: continuation result found=%d error=%d\n",
            result->found, result->errorCode);
    }
    return rescueContext.callerReturnAddress;
}

static void *rescueCodeAddress(void *pointer) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(pointer, ptrauth_key_function_pointer);
#else
    return pointer;
#endif
}

static int rescueInstallDirectBranch(void *target, void *replacement) {
    target = rescueCodeAddress(target);
    replacement = rescueCodeAddress(replacement);
    if (getenv("RANGE_SEED_SURGERY_DEBUG") != NULL) {
        fprintf(stderr, "range seed surgery: target=%p replacement=%p\n",
            target, replacement);
    }

    const long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) {
        return 2;
    }
    const uintptr_t targetAddress = (uintptr_t)target;
    const uintptr_t pageAddress = targetAddress & ~((uintptr_t)pageSize - 1);
    kern_return_t protection = mach_vm_protect(
        mach_task_self(),
        (mach_vm_address_t)pageAddress,
        (mach_vm_size_t)pageSize,
        FALSE,
        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY
    );
    if (protection != KERN_SUCCESS) {
        return 3;
    }

    const intptr_t displacement = (intptr_t)replacement - (intptr_t)target;
    if ((displacement & 3) != 0
        || displacement < -(1LL << 27)
        || displacement >= (1LL << 27)) {
        return 5;
    }
    const uint32_t branch = 0x14000000U
        | ((uint32_t)(displacement >> 2) & 0x03ffffffU);
    memcpy(target, &branch, sizeof(branch));
    __builtin___clear_cache((char *)target, (char *)target + sizeof(branch));
    protection = mach_vm_protect(
        mach_task_self(),
        (mach_vm_address_t)pageAddress,
        (mach_vm_size_t)pageSize,
        FALSE,
        VM_PROT_READ | VM_PROT_EXECUTE
    );
    if (protection != KERN_SUCCESS) {
        return 4;
    }
    return 0;
}

static int rescueInstallTwoInstructionCave(
    void *target,
    uint32_t firstInstruction,
    void *branchTarget
) {
    target = rescueCodeAddress(target);
    branchTarget = rescueCodeAddress(branchTarget);
    const intptr_t displacement = (intptr_t)branchTarget
        - ((intptr_t)target + 4);
    if ((displacement & 3) != 0
        || displacement < -(1LL << 27)
        || displacement >= (1LL << 27)) {
        return 5;
    }
    const uint32_t branch = 0x14000000U
        | ((uint32_t)(displacement >> 2) & 0x03ffffffU);
    const long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) {
        return 2;
    }
    const uintptr_t pageAddress = (uintptr_t)target
        & ~((uintptr_t)pageSize - 1);
    kern_return_t protection = mach_vm_protect(
        mach_task_self(),
        (mach_vm_address_t)pageAddress,
        (mach_vm_size_t)pageSize,
        FALSE,
        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY
    );
    if (protection != KERN_SUCCESS) {
        return 3;
    }
    memcpy(target, &firstInstruction, sizeof(firstInstruction));
    memcpy((uint8_t *)target + 4, &branch, sizeof(branch));
    __builtin___clear_cache((char *)target, (char *)target + 8);
    protection = mach_vm_protect(
        mach_task_self(),
        (mach_vm_address_t)pageAddress,
        (mach_vm_size_t)pageSize,
        FALSE,
        VM_PROT_READ | VM_PROT_EXECUTE
    );
    return protection == KERN_SUCCESS ? 0 : 4;
}

static int rescueInstallAbsoluteBranch(const char *symbol, void *replacement) {
    void *target = dlsym(RTLD_DEFAULT, symbol);
    if (target == NULL) {
        return 1;
    }
    return rescueInstallDirectBranch(target, replacement);
}

__attribute__((constructor))
static void rescueInstall(void) {
    const char *mode = getenv("RANGE_SEED_SURGERY_MODE");
    if (mode == NULL) {
        return;
    }
    const char *symbol = NULL;
    void *replacement = NULL;
    if (strcmp(mode, "probe") == 0) {
        symbol = "compilerBProjectModeAssembly";
        replacement = (void *)&rescueProjectModeAssembly;
    } else if (strcmp(mode, "continuation-probe") == 0) {
        symbol = "compilerBLowerEarlyReturnExecutionCompass";
        replacement = (void *)&rescueLowerEarlyReturnEntry;
    } else {
        return;
    }
    int result = 0;
    if (strcmp(mode, "continuation-probe") == 0) {
        void *original = dlsym(RTLD_DEFAULT,
            "compilerBLowerEarlyReturnExecutionCompass");
        void *entryCave = dlsym(RTLD_DEFAULT, "compilerBEmitProjectLLVM");
        void *bodyCave = dlsym(RTLD_DEFAULT, "compilerBProjectLLVMType");
        if (original == NULL || entryCave == NULL || bodyCave == NULL) {
            result = 1;
        } else {
            result = rescueInstallTwoInstructionCave(
                bodyCave,
                0xa9ba6ffcU,
                (uint8_t *)original + 4
            );
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                entryCave,
                0xd503245fU,
                bodyCave
            );
        }
        if (result == 0) {
            rescueOriginalLowerEarlyReturnAddress = entryCave;
        }
        void *append = dlsym(RTLD_DEFAULT,
            "compilerBExecutionCompassAppendExternLocal");
        void *appendEntryCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMLowerProcess");
        void *appendBodyCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMExpressionOperand");
        if (result == 0
            && (append == NULL || appendEntryCave == NULL
                || appendBodyCave == NULL)) {
            result = 1;
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                appendBodyCave,
                0xa9ba6ffcU,
                (uint8_t *)append + 4
            );
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                appendEntryCave,
                0xd503245fU,
                appendBodyCave
            );
        }
        if (result == 0) {
            rescueAppendExternLocalAddress = appendEntryCave;
        }
        rescueLocalRowAddress = dlsym(
            RTLD_DEFAULT, "compilerBExecutionCompassLocalRow");
        if (result == 0 && rescueLocalRowAddress == NULL) {
            result = 1;
        }
        void *predicateCount = dlsym(RTLD_DEFAULT,
            "compilerBExecutionCompassPredicateCount");
        void *predicateCountEntryCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMFunctionDefinition");
        void *predicateCountBodyCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMLowerExpression");
        if (result == 0
            && (predicateCount == NULL || predicateCountEntryCave == NULL
                || predicateCountBodyCave == NULL)) {
            result = 1;
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                predicateCountBodyCave,
                0xd10503ffU,
                (uint8_t *)predicateCount + 4
            );
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                predicateCountEntryCave,
                0xd503245fU,
                predicateCountBodyCave
            );
        }
        if (result == 0) {
            rescuePredicateCountAddress = predicateCountEntryCave;
        }
        void *appendPredicate = dlsym(RTLD_DEFAULT,
            "compilerBExecutionCompassAppendPredicate");
        void *appendPredicateEntryCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMLowerLeaf");
        void *appendPredicateBodyCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMReachabilityAppend");
        if (result == 0
            && (appendPredicate == NULL || appendPredicateEntryCave == NULL
                || appendPredicateBodyCave == NULL)) {
            result = 1;
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                appendPredicateBodyCave,
                0xa9ba6ffcU,
                (uint8_t *)appendPredicate + 4
            );
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                appendPredicateEntryCave,
                0xd503245fU,
                appendPredicateBodyCave
            );
        }
        if (result == 0) {
            rescueAppendPredicateAddress = appendPredicateEntryCave;
        }
        void *appendReturnPath = dlsym(RTLD_DEFAULT,
            "compilerBExecutionCompassAppendReturnPath");
        void *appendReturnPathEntryCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMReachabilityCount");
        void *appendReturnPathBodyCave = dlsym(RTLD_DEFAULT,
            "compilerBProjectLLVMReachabilityElement");
        if (result == 0
            && (appendReturnPath == NULL || appendReturnPathEntryCave == NULL
                || appendReturnPathBodyCave == NULL)) {
            result = 1;
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                appendReturnPathBodyCave,
                0xa9ba6ffcU,
                (uint8_t *)appendReturnPath + 4
            );
        }
        if (result == 0) {
            result = rescueInstallTwoInstructionCave(
                appendReturnPathEntryCave,
                0xd503245fU,
                appendReturnPathBodyCave
            );
        }
        if (result == 0) {
            rescueAppendReturnPathAddress = appendReturnPathEntryCave;
        }
    }
    if (result == 0) {
        result = rescueInstallAbsoluteBranch(symbol, replacement);
    }
    if (result != 0 && dlsym(RTLD_DEFAULT, "compilerBEntry") != NULL) {
        fprintf(stderr, "range seed surgery: probe patch failed status=%d errno=%d\n",
            result, errno);
        _Exit(70);
    }
}
