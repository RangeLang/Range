#include "native.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* ---- growable text ------------------------------------------------------ */

static void *grow(void *items, size_t *capacity, size_t need, size_t size)
{
    if (need <= *capacity) return items;
    size_t next = *capacity ? *capacity * 2 : 64;
    while (next < need) next *= 2;
    void *grown = realloc(items, next * size);
    if (!grown) abort();
    *capacity = next;
    return grown;
}

void rangeMachineFree(RangeMachine *machine)
{
    free(machine->bytes);
    free(machine->uses);
    free(machine->symbols);
    memset(machine, 0, sizeof(*machine));
}

size_t rangeEmitBytes(RangeMachine *machine, const void *bytes, size_t size)
{
    size_t at = machine->size;
    machine->bytes = grow(machine->bytes,&machine->capacity,machine->size + size,1);
    memcpy(machine->bytes + machine->size,bytes,size);
    machine->size += size;
    return at;
}

size_t rangeEmit(RangeMachine *machine, uint32_t instruction)
{
    uint8_t bytes[4] = {(uint8_t)instruction,(uint8_t)(instruction >> 8),(uint8_t)(instruction >> 16),(uint8_t)(instruction >> 24)};
    return rangeEmitBytes(machine,bytes,4);
}

void rangePatch(RangeMachine *machine, size_t at, uint32_t instruction)
{
    machine->bytes[at] = (uint8_t)instruction;
    machine->bytes[at + 1] = (uint8_t)(instruction >> 8);
    machine->bytes[at + 2] = (uint8_t)(instruction >> 16);
    machine->bytes[at + 3] = (uint8_t)(instruction >> 24);
}

void rangeAlign(RangeMachine *machine, size_t alignment)
{
    static const uint8_t zero[16] = {0};
    while (machine->size % alignment) rangeEmitBytes(machine,zero,1);
}

void rangeCallImport(RangeMachine *machine, const char *symbol)
{
    size_t index = 0;
    while (index < machine->symbolCount && strcmp(machine->symbols[index],symbol)) ++index;
    if (index == machine->symbolCount) {
        machine->symbols = grow(machine->symbols,&machine->symbolCapacity,machine->symbolCount + 1,sizeof(*machine->symbols));
        machine->symbols[machine->symbolCount++] = symbol;
    }
    machine->uses = grow(machine->uses,&machine->useCapacity,machine->useCount + 1,sizeof(*machine->uses));
    machine->uses[machine->useCount++] = (RangeImportUse){.at=machine->size,.symbol=index};
    rangeEmit(machine,0x90000010u); /* adrp x16, slot page (patched) */
    rangeEmit(machine,0xF9400210u); /* ldr x16, [x16, slot offset] (patched) */
    rangeEmit(machine,armBlr(16));
}

/* ---- SHA-256 (FIPS 180-4), for code signature page hashes --------------- */

static uint32_t rotr(uint32_t x, int n) { return x >> n | x << (32 - n); }

void rangeSha256(const uint8_t *data, size_t size, uint8_t digest[32])
{
    static const uint32_t k[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    uint32_t h[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    size_t total = (size + 9 + 63) / 64 * 64;
    for (size_t block = 0; block < total; block += 64) {
        uint8_t chunk[64];
        for (size_t i = 0; i < 64; ++i) {
            size_t at = block + i;
            if (at < size) chunk[i] = data[at];
            else if (at == size) chunk[i] = 0x80;
            else if (at >= total - 8) chunk[i] = (uint8_t)(((uint64_t)size * 8) >> (8 * (total - 1 - at)));
            else chunk[i] = 0;
        }
        uint32_t w[64];
        for (int i = 0; i < 16; ++i)
            w[i] = (uint32_t)chunk[4*i] << 24 | (uint32_t)chunk[4*i+1] << 16 | (uint32_t)chunk[4*i+2] << 8 | chunk[4*i+3];
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = rotr(w[i-15],7) ^ rotr(w[i-15],18) ^ (w[i-15] >> 3);
            uint32_t s1 = rotr(w[i-2],17) ^ rotr(w[i-2],19) ^ (w[i-2] >> 10);
            w[i] = w[i-16] + s0 + w[i-7] + s1;
        }
        uint32_t a=h[0], b=h[1], c=h[2], d=h[3], e=h[4], f=h[5], g=h[6], hh=h[7];
        for (int i = 0; i < 64; ++i) {
            uint32_t t1 = hh + (rotr(e,6) ^ rotr(e,11) ^ rotr(e,25)) + ((e & f) ^ (~e & g)) + k[i] + w[i];
            uint32_t t2 = (rotr(a,2) ^ rotr(a,13) ^ rotr(a,22)) + ((a & b) ^ (a & c) ^ (b & c));
            hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
    }
    for (int i = 0; i < 8; ++i) {
        digest[4*i] = (uint8_t)(h[i] >> 24); digest[4*i+1] = (uint8_t)(h[i] >> 16);
        digest[4*i+2] = (uint8_t)(h[i] >> 8); digest[4*i+3] = (uint8_t)h[i];
    }
}

/* ---- Mach-O ---------------------------------------------------------------
 * Layout, all page-aligned (16 KB):
 *   __PAGEZERO | __TEXT: header, load commands, __text | __DATA_CONST: __got
 *   | __LINKEDIT: chained fixups, code signature
 * dyld binds each GOT slot to a libSystem symbol; code reaches a slot with
 * adrp/ldr. The signature is ad-hoc and linker-style: one CodeDirectory with a
 * SHA-256 hash per 4 KB page, so no signing tool is involved. */

enum { Page = 0x4000, SignaturePage = 0x1000 };
static const uint64_t Base = 0x100000000ull;

typedef struct { uint8_t *bytes; size_t size, capacity; } Bytes;

static void put(Bytes *out, const void *data, size_t size)
{
    out->bytes = grow(out->bytes,&out->capacity,out->size + size,1);
    memcpy(out->bytes + out->size,data,size);
    out->size += size;
}
static void put8(Bytes *out, uint8_t v) { put(out,&v,1); }
static void put16(Bytes *out, uint16_t v) { put8(out,(uint8_t)v); put8(out,(uint8_t)(v >> 8)); }
static void put32(Bytes *out, uint32_t v) { put16(out,(uint16_t)v); put16(out,(uint16_t)(v >> 16)); }
static void put64(Bytes *out, uint64_t v) { put32(out,(uint32_t)v); put32(out,(uint32_t)(v >> 32)); }
static void putBig32(Bytes *out, uint32_t v) { put8(out,(uint8_t)(v >> 24)); put8(out,(uint8_t)(v >> 16)); put8(out,(uint8_t)(v >> 8)); put8(out,(uint8_t)v); }
static void putBig64(Bytes *out, uint64_t v) { putBig32(out,(uint32_t)(v >> 32)); putBig32(out,(uint32_t)v); }
static void putName(Bytes *out, const char *name, size_t width) { char buffer[16] = {0}; strncpy(buffer,name,width); put(out,buffer,width); }
static void pad(Bytes *out, size_t alignment) { while (out->size % alignment) put8(out,0); }
static size_t roundUp(size_t value, size_t alignment) { return (value + alignment - 1) / alignment * alignment; }

static void segment(Bytes *out, const char *name, uint64_t address, uint64_t memorySize, uint64_t fileOffset,
                    uint64_t fileSize, uint32_t protection, uint32_t flags, int sections)
{
    put32(out,0x19); put32(out,72 + 80 * (uint32_t)sections); putName(out,name,16);
    put64(out,address); put64(out,memorySize); put64(out,fileOffset); put64(out,fileSize);
    put32(out,protection); put32(out,protection); put32(out,(uint32_t)sections); put32(out,flags);
}

static void section(Bytes *out, const char *name, const char *segmentName, uint64_t address, uint64_t size,
                    uint32_t offset, uint32_t alignment, uint32_t flags)
{
    putName(out,name,16); putName(out,segmentName,16);
    put64(out,address); put64(out,size); put32(out,offset); put32(out,alignment);
    put32(out,0); put32(out,0); put32(out,flags); put32(out,0); put32(out,0); put32(out,0);
}

static void stringCommand(Bytes *out, uint32_t command, const uint32_t *prefix, size_t words, const char *text)
{
    size_t size = roundUp(8 + 4 * words + strlen(text) + 1,8);
    size_t start = out->size;
    put32(out,command); put32(out,(uint32_t)size);
    for (size_t i = 0; i < words; ++i) put32(out,prefix[i]);
    put(out,text,strlen(text) + 1);
    while (out->size < start + size) put8(out,0);
}

/* Load commands; offsets that depend on the final layout are parameters. */
static void loadCommands(Bytes *out, uint32_t *count, size_t codeOffset, size_t textSize, size_t textSegment,
                         size_t gotSize, size_t fixupsOffset, size_t fixupsSize, size_t signatureOffset, size_t signatureSize)
{
    int imports = gotSize != 0;
    size_t dataSegment = imports ? Page : 0;
    uint64_t linkedit = Base + textSegment + dataSegment;
    *count = 0;
    segment(out,"__PAGEZERO",0,Base,0,0,0,0,0); ++*count;
    segment(out,"__TEXT",Base,textSegment,0,textSegment,5,0,1); ++*count;
    section(out,"__text","__TEXT",Base + codeOffset,textSize,(uint32_t)codeOffset,4,0x80000400); /* align 2^4 */
    if (imports) {
        segment(out,"__DATA_CONST",Base + textSegment,Page,textSegment,Page,3,0x10,1); ++*count; /* SG_READ_ONLY */
        section(out,"__got","__DATA_CONST",Base + textSegment,gotSize,(uint32_t)textSegment,3,0x6); /* non-lazy pointers */
    }
    size_t linkeditSize = signatureOffset + signatureSize - fixupsOffset;
    segment(out,"__LINKEDIT",linkedit,roundUp(linkeditSize ? linkeditSize : 1,Page),fixupsOffset,linkeditSize,1,0,0); ++*count;
    put32(out,0x80000034); put32(out,16); put32(out,(uint32_t)fixupsOffset); put32(out,(uint32_t)fixupsSize); ++*count;
    uint32_t dylinker[] = {12};
    stringCommand(out,0xE,dylinker,1,"/usr/lib/dyld"); ++*count;
    uint32_t dylib[] = {24,2,0x10000,0x10000};
    stringCommand(out,0xC,dylib,4,"/usr/lib/libSystem.B.dylib"); ++*count;
    put32(out,0x32); put32(out,24); put32(out,1); put32(out,0x000E0000); put32(out,0x000E0000); put32(out,0); ++*count; /* macOS 14 */
    put32(out,0x80000028); put32(out,24); put64(out,codeOffset); put64(out,0); ++*count; /* LC_MAIN; entry patched by caller */
    put32(out,0x1D); put32(out,16); put32(out,(uint32_t)signatureOffset); put32(out,(uint32_t)signatureSize); ++*count;
}

/* Chained fixups: every import is a bind in the GOT, chained 8 bytes apart. */
static void chainedFixups(Bytes *out, RangeMachine *machine, int segments)
{
    Bytes names = {0};
    put8(&names,0);
    uint32_t *nameOffsets = calloc(machine->symbolCount ? machine->symbolCount : 1,sizeof(*nameOffsets));
    if (!nameOffsets) abort();
    for (size_t i = 0; i < machine->symbolCount; ++i) {
        nameOffsets[i] = (uint32_t)names.size;
        put(&names,machine->symbols[i],strlen(machine->symbols[i]) + 1);
    }
    uint32_t startsOffset = 32, startsSize = 4 + 4 * (uint32_t)segments;
    uint32_t segmentStartsSize = machine->symbolCount ? 24 : 0;
    uint32_t importsOffset = startsOffset + startsSize + segmentStartsSize;
    uint32_t symbolsOffset = importsOffset + 4 * (uint32_t)machine->symbolCount;
    put32(out,0); put32(out,startsOffset); put32(out,importsOffset); put32(out,symbolsOffset);
    put32(out,(uint32_t)machine->symbolCount); put32(out,1); put32(out,0); put32(out,0);
    put32(out,(uint32_t)segments);
    for (int i = 0; i < segments; ++i) put32(out,machine->symbolCount && i == 2 ? startsSize : 0); /* __DATA_CONST is segment 2 */
    if (machine->symbolCount) {
        put32(out,24); put16(out,Page); put16(out,6); /* DYLD_CHAINED_PTR_64_OFFSET */
        put64(out,0); /* segment offset from the image base; written below */
        put32(out,0); put16(out,1); put16(out,0);   /* one page, chain starts at 0 */
    }
    for (size_t i = 0; i < machine->symbolCount; ++i) put32(out,1u | nameOffsets[i] << 9); /* library ordinal 1: libSystem */
    put(out,names.bytes,names.size);
    pad(out,8);
    free(names.bytes);
    free(nameOffsets);
}

int rangeWriteExecutable(RangeMachine *machine, size_t entry, const char *path, char *error, size_t errorSize)
{
    int imports = machine->symbolCount != 0;
    int segments = imports ? 4 : 3;
    size_t gotSize = 8 * machine->symbolCount;
    // First pass sizes the load commands; code starts after them, with room
    // left for nothing else. Offsets inside the commands do not change size.
    Bytes probe = {0};
    uint32_t count = 0;
    loadCommands(&probe,&count,0,0,0,gotSize,0,0,0,0);
    size_t codeOffset = roundUp(32 + probe.size,16);
    free(probe.bytes);
    size_t textSegment = roundUp(codeOffset + machine->size,Page);
    size_t fixupsOffset = textSegment + (imports ? Page : 0);
    Bytes fixups = {0};
    chainedFixups(&fixups,machine,segments);
    if (imports) {
        uint64_t segmentOffset = textSegment;
        memcpy(fixups.bytes + 32 + 4 + 4 * segments + 8,&segmentOffset,8); /* little-endian host */
    }
    size_t signatureOffset = roundUp(fixupsOffset + fixups.size,16);
    const char *slash = strrchr(path,'/');
    const char *identifier = slash ? slash + 1 : path;
    size_t slots = (signatureOffset + SignaturePage - 1) / SignaturePage;
    size_t directorySize = 88 + strlen(identifier) + 1 + 32 * slots;
    size_t signatureSize = roundUp(20 + directorySize,16);

    Bytes image = {0};
    put32(&image,0xFEEDFACF); put32(&image,0x0100000C); put32(&image,0); put32(&image,2);
    Bytes commands = {0};
    loadCommands(&commands,&count,codeOffset,machine->size,textSegment,gotSize,fixupsOffset,fixups.size,signatureOffset,signatureSize);
    // LC_MAIN's entry offset is the __text offset of the entry function.
    for (size_t at = 0; at + 24 <= commands.size;) {
        uint32_t command, size;
        memcpy(&command,commands.bytes + at,4); memcpy(&size,commands.bytes + at + 4,4);
        if (command == 0x80000028) { uint64_t offset = codeOffset + entry; memcpy(commands.bytes + at + 8,&offset,8); }
        at += size;
    }
    put32(&image,count); put32(&image,(uint32_t)commands.size); put32(&image,0x200085); put32(&image,0);
    put(&image,commands.bytes,commands.size);
    free(commands.bytes);
    while (image.size < codeOffset) put8(&image,0);
    size_t textAt = image.size;
    put(&image,machine->bytes,machine->size);
    // Bind each adrp/ldr pair to its GOT slot now that addresses are final.
    for (size_t i = 0; i < machine->useCount; ++i) {
        size_t at = textAt + machine->uses[i].at;
        uint64_t pc = Base + at, slot = Base + textSegment + 8 * machine->uses[i].symbol;
        int64_t pages = (int64_t)(slot >> 12) - (int64_t)(pc >> 12);
        uint32_t adrp = 0x90000010u | ((uint32_t)pages & 3u) << 29 | (((uint32_t)pages >> 2) & 0x7FFFFu) << 5;
        uint32_t ldr = 0xF9400210u | (uint32_t)((slot & 0xFFF) / 8) << 10;
        memcpy(image.bytes + at,&adrp,4); memcpy(image.bytes + at + 4,&ldr,4);
    }
    while (image.size < textSegment) put8(&image,0);
    if (imports) {
        for (size_t i = 0; i < machine->symbolCount; ++i)
            put64(&image,(uint64_t)i | (uint64_t)(i + 1 < machine->symbolCount ? 2 : 0) << 51 | 1ull << 63);
        while (image.size < textSegment + Page) put8(&image,0);
    }
    put(&image,fixups.bytes,fixups.size);
    free(fixups.bytes);
    while (image.size < signatureOffset) put8(&image,0);
    // Code signature: SuperBlob { CodeDirectory }, big-endian.
    size_t signatureStart = image.size;
    putBig32(&image,0xFADE0CC0); putBig32(&image,(uint32_t)(20 + directorySize)); putBig32(&image,1);
    putBig32(&image,0); putBig32(&image,20);
    putBig32(&image,0xFADE0C02); putBig32(&image,(uint32_t)directorySize); putBig32(&image,0x20400);
    putBig32(&image,0x20002); /* adhoc, linker-signed */
    putBig32(&image,(uint32_t)(88 + strlen(identifier) + 1)); putBig32(&image,88);
    putBig32(&image,0); putBig32(&image,(uint32_t)slots); putBig32(&image,(uint32_t)signatureOffset);
    put8(&image,32); put8(&image,2); put8(&image,0); put8(&image,12); /* SHA-256, 4 KB pages */
    putBig32(&image,0); putBig32(&image,0); putBig32(&image,0); putBig32(&image,0);
    putBig64(&image,0); putBig64(&image,0); putBig64(&image,textSegment); putBig64(&image,1); /* main binary */
    put(&image,identifier,strlen(identifier) + 1);
    for (size_t i = 0; i < slots; ++i) {
        uint8_t digest[32];
        size_t start = i * SignaturePage, size = signatureOffset - start < SignaturePage ? signatureOffset - start : SignaturePage;
        rangeSha256(image.bytes + start,size,digest);
        put(&image,digest,32);
    }
    while (image.size < signatureStart + signatureSize) put8(&image,0);

    FILE *file = fopen(path,"wb");
    int ok = file && fwrite(image.bytes,1,image.size,file) == image.size;
    if (file && fclose(file)) ok = 0;
    if (ok && chmod(path,0755)) ok = 0;
    if (!ok) snprintf(error,errorSize,"cannot write %s: %s",path,strerror(errno));
    free(image.bytes);
    return ok;
}
