/* Native output: ARM64 machine code in a signed Mach-O executable for Apple
 * silicon. This is a C mechanism; Range declarations supply every type,
 * width, and law the compiler lowers into it. */
#ifndef RANGE_COMPILER_NATIVE_H
#define RANGE_COMPILER_NATIVE_H

#include <stddef.h>
#include <stdint.h>

/* An adrp/ldr pair at `at` loads the GOT slot of import `symbol`. */
typedef struct {
    size_t at;
    size_t symbol;
} RangeImportUse;

/* The __text contents: machine code followed by read-only data. */
typedef struct {
    uint8_t *bytes;
    size_t size, capacity;
    RangeImportUse *uses;
    size_t useCount, useCapacity;
    const char **symbols; /* imported from libSystem, e.g. "_write" */
    size_t symbolCount, symbolCapacity;
} RangeMachine;

void rangeMachineFree(RangeMachine *machine);
size_t rangeEmit(RangeMachine *machine, uint32_t instruction);
void rangePatch(RangeMachine *machine, size_t at, uint32_t instruction);
size_t rangeEmitBytes(RangeMachine *machine, const void *bytes, size_t size);
void rangeAlign(RangeMachine *machine, size_t alignment);
/* Call a libSystem function through its GOT slot: adrp x16, ldr x16, blr x16. */
void rangeCallImport(RangeMachine *machine, const char *symbol);
/* Lay out, bind, sign, and write the executable. `entry` is a __text offset. */
int rangeWriteExecutable(RangeMachine *machine, size_t entry, const char *path,
                         char *error, size_t errorSize);
void rangeSha256(const uint8_t *data, size_t size, uint8_t digest[32]);

/* ARM64 condition codes. */
enum {
    RangeEQ = 0, RangeNE = 1, RangeHS = 2, RangeLO = 3, RangeVS = 6, RangeVC = 7,
    RangeHI = 8, RangeLS = 9, RangeGE = 10, RangeLT = 11, RangeGT = 12, RangeLE = 13
};

/* 64-bit instruction encodings used by the code generator. Register 31 is
 * xzr or sp depending on the instruction. */
static inline uint32_t armMovz(int rd, uint16_t imm, int shift) { return 0xD2800000u | (uint32_t)(shift / 16) << 21 | (uint32_t)imm << 5 | (uint32_t)rd; }
static inline uint32_t armMovk(int rd, uint16_t imm, int shift) { return 0xF2800000u | (uint32_t)(shift / 16) << 21 | (uint32_t)imm << 5 | (uint32_t)rd; }
static inline uint32_t armMov(int rd, int rm) { return 0xAA0003E0u | (uint32_t)rm << 16 | (uint32_t)rd; }
static inline uint32_t armAdd(int rd, int rn, int rm) { return 0x8B000000u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armAdds(int rd, int rn, int rm) { return 0xAB000000u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armSub(int rd, int rn, int rm) { return 0xCB000000u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armSubs(int rd, int rn, int rm) { return 0xEB000000u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armAddImm(int rd, int rn, uint32_t imm) { return 0x91000000u | imm << 10 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armSubImm(int rd, int rn, uint32_t imm) { return 0xD1000000u | imm << 10 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armCmp(int rn, int rm) { return armSubs(31,rn,rm); }
static inline uint32_t armCmpImm(int rn, uint32_t imm) { return 0xF100001Fu | imm << 10 | (uint32_t)rn << 5; }
static inline uint32_t armCmnImm(int rn, uint32_t imm) { return 0xB100001Fu | imm << 10 | (uint32_t)rn << 5; }
/* cmp rn, rm, asr #63: rn equals the sign extension of rm's top bit. */
static inline uint32_t armCmpAsr63(int rn, int rm) { return 0xEB80FC1Fu | (uint32_t)rm << 16 | (uint32_t)rn << 5; }
static inline uint32_t armMul(int rd, int rn, int rm) { return 0x9B007C00u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armMsub(int rd, int rn, int rm, int ra) { return 0x9B008000u | (uint32_t)rm << 16 | (uint32_t)ra << 10 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armSmulh(int rd, int rn, int rm) { return 0x9B407C00u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armUmulh(int rd, int rn, int rm) { return 0x9BC07C00u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armSdiv(int rd, int rn, int rm) { return 0x9AC00C00u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armUdiv(int rd, int rn, int rm) { return 0x9AC00800u | (uint32_t)rm << 16 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armNeg(int rd, int rm) { return armSub(rd,31,rm); }
static inline uint32_t armNegs(int rd, int rm) { return armSubs(rd,31,rm); }
/* sbfx/ubfx rd, rn, #0, #bits: the low `bits` bits, sign- or zero-extended. */
static inline uint32_t armSbfx(int rd, int rn, int bits) { return 0x93400000u | (uint32_t)(bits - 1) << 10 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armUbfx(int rd, int rn, int bits) { return 0xD3400000u | (uint32_t)(bits - 1) << 10 | (uint32_t)rn << 5 | (uint32_t)rd; }
static inline uint32_t armCset(int rd, int cond) { return 0x9A9F07E0u | (uint32_t)(cond ^ 1) << 12 | (uint32_t)rd; }
static inline uint32_t armB(int32_t words) { return 0x14000000u | ((uint32_t)words & 0x3FFFFFFu); }
static inline uint32_t armBl(int32_t words) { return 0x94000000u | ((uint32_t)words & 0x3FFFFFFu); }
static inline uint32_t armBcond(int cond, int32_t words) { return 0x54000000u | ((uint32_t)words & 0x7FFFFu) << 5 | (uint32_t)cond; }
static inline uint32_t armCbz(int rt, int32_t words) { return 0xB4000000u | ((uint32_t)words & 0x7FFFFu) << 5 | (uint32_t)rt; }
static inline uint32_t armCbnz(int rt, int32_t words) { return 0xB5000000u | ((uint32_t)words & 0x7FFFFu) << 5 | (uint32_t)rt; }
static inline uint32_t armBlr(int rn) { return 0xD63F0000u | (uint32_t)rn << 5; }
static inline uint32_t armRet(void) { return 0xD65F03C0u; }
static inline uint32_t armBrk(uint16_t imm) { return 0xD4200000u | (uint32_t)imm << 5; }
static inline uint32_t armAdr(int rd, int32_t bytes) { return 0x10000000u | ((uint32_t)bytes & 3u) << 29 | (((uint32_t)bytes >> 2) & 0x7FFFFu) << 5 | (uint32_t)rd; }
/* Frame and stack: stp/ldp x29, x30; push/pop one register keeping sp 16-aligned. */
static inline uint32_t armPushFrame(void) { return 0xA9BF7BFDu; }
static inline uint32_t armPopFrame(void) { return 0xA8C17BFDu; }
static inline uint32_t armPush(int rt) { return 0xF81F0FE0u | (uint32_t)rt; }
static inline uint32_t armPop(int rt) { return 0xF84107E0u | (uint32_t)rt; }
/* stur/ldur rt, [rn, #offset] for offsets in -256..255. */
static inline uint32_t armStur(int rt, int rn, int32_t offset) { return 0xF8000000u | ((uint32_t)offset & 0x1FFu) << 12 | (uint32_t)rn << 5 | (uint32_t)rt; }
static inline uint32_t armLdur(int rt, int rn, int32_t offset) { return 0xF8400000u | ((uint32_t)offset & 0x1FFu) << 12 | (uint32_t)rn << 5 | (uint32_t)rt; }
static inline uint32_t armStr(int rt, int rn, uint32_t offset) { return 0xF9000000u | (offset / 8) << 10 | (uint32_t)rn << 5 | (uint32_t)rt; }
static inline uint32_t armLdr(int rt, int rn, uint32_t offset) { return 0xF9400000u | (offset / 8) << 10 | (uint32_t)rn << 5 | (uint32_t)rt; }

#endif
