.text
.p2align 2
.globl _rescueLowerEarlyReturnEntry
_rescueLowerEarlyReturnEntry:
    mov x9, sp
    mov x10, x30
    sub sp, sp, #96
    stp x29, x30, [sp, #80]
    add x29, sp, #80

    stp x1, x2, [sp]
    stp x3, x4, [sp, #16]
    stp x5, x6, [sp, #32]
    str x7, [sp, #48]
    str x0, [sp, #56]

    mov x1, sp
    mov x2, x9
    ldr w3, [x9, #0x8c]
    add x4, x9, #0x90
    add x5, x9, #0xc8
    ldr w6, [x9, #0x178]
    mov x7, x10
    bl _rescueLowerEarlyReturn

    ldr x0, [sp, #56]
    ldp x1, x2, [sp]
    ldp x3, x4, [sp, #16]
    ldp x5, x6, [sp, #32]
    ldr x7, [sp, #48]
    ldp x29, x30, [sp, #80]
    add sp, sp, #96
    adr x30, LrescueLowerEarlyReturnAfter
    adrp x16, _rescueOriginalLowerEarlyReturnAddress@PAGE
    ldr x16, [x16, _rescueOriginalLowerEarlyReturnAddress@PAGEOFF]
    br x16

LrescueLowerEarlyReturnAfter:
    bl _rescueLowerEarlyReturnAfter
    br x0

.p2align 2
.globl _rescueInvokeAppendExternLocal
_rescueInvokeAppendExternLocal:
    sub sp, sp, #0x1e0
    stp x19, x20, [sp, #0x180]
    stp x21, x22, [sp, #0x190]
    stp x23, x24, [sp, #0x1a0]
    stp x25, x26, [sp, #0x1b0]
    stp x29, x30, [sp, #0x1d0]
    add x29, sp, #0x1d0

    mov x19, x0
    mov x20, x1
    mov w21, w2
    mov w22, w3
    mov x23, x4
    mov x24, x5
    mov w25, w6
    mov w26, w7

    mov x0, sp
    add x1, x20, #8
    mov x2, #0x84
    bl _memcpy
    str w21, [sp, #0x84]
    str w22, [sp, #0x88]
    add x0, sp, #0x90
    mov x1, x23
    mov x2, #56
    bl _memcpy
    add x0, sp, #0xc8
    mov x1, x24
    mov x2, #176
    bl _memcpy
    str w25, [sp, #0x178]
    str w26, [sp, #0x17c]

    ldp x0, x1, [x19]
    ldp x2, x3, [x19, #16]
    ldp x4, x5, [x19, #32]
    ldr x6, [x19, #48]
    ldr x7, [x20]
    adr x30, LrescueAppendExternLocalAfter
    adrp x16, _rescueAppendExternLocalAddress@PAGE
    ldr x16, [x16, _rescueAppendExternLocalAddress@PAGEOFF]
    br x16

LrescueAppendExternLocalAfter:
    ldp x19, x20, [sp, #0x180]
    ldp x21, x22, [sp, #0x190]
    ldp x23, x24, [sp, #0x1a0]
    ldp x25, x26, [sp, #0x1b0]
    ldp x29, x30, [sp, #0x1d0]
    add sp, sp, #0x1e0
    ret

.p2align 2
.globl _rescueInvokeLocalRow
_rescueInvokeLocalRow:
    sub sp, sp, #0x90
    stp x19, x20, [sp, #0x60]
    stp x21, x22, [sp, #0x70]
    stp x29, x30, [sp, #0x80]
    add x29, sp, #0x80
    mov x19, x0
    mov w20, w1
    mov w21, w2

    mov x0, sp
    add x1, x19, #0x40
    mov x2, #0x4c
    bl _memcpy
    str w20, [sp, #0x4c]
    str w21, [sp, #0x50]
    ldp x0, x1, [x19]
    ldp x2, x3, [x19, #16]
    ldp x4, x5, [x19, #32]
    ldp x6, x7, [x19, #48]
    adr x30, LrescueLocalRowAfter
    adrp x16, _rescueLocalRowAddress@PAGE
    ldr x16, [x16, _rescueLocalRowAddress@PAGEOFF]
    br x16

LrescueLocalRowAfter:
    ldp x19, x20, [sp, #0x60]
    ldp x21, x22, [sp, #0x70]
    ldp x29, x30, [sp, #0x80]
    add sp, sp, #0x90
    ret

.p2align 2
.globl _rescueInvokePredicateCount
_rescueInvokePredicateCount:
    sub sp, sp, #0x90
    stp x19, x20, [sp, #0x60]
    stp x29, x30, [sp, #0x80]
    add x29, sp, #0x80
    mov x19, x0
    mov w20, w1

    mov x0, sp
    add x1, x19, #0x40
    mov x2, #0x4c
    bl _memcpy
    str w20, [sp, #0x4c]
    ldp x0, x1, [x19]
    ldp x2, x3, [x19, #16]
    ldp x4, x5, [x19, #32]
    ldp x6, x7, [x19, #48]
    adr x30, LrescuePredicateCountAfter
    adrp x16, _rescuePredicateCountAddress@PAGE
    ldr x16, [x16, _rescuePredicateCountAddress@PAGEOFF]
    br x16

LrescuePredicateCountAfter:
    ldp x19, x20, [sp, #0x60]
    ldp x29, x30, [sp, #0x80]
    add sp, sp, #0x90
    ret

.p2align 2
.globl _rescueInvokeAppendPredicate
_rescueInvokeAppendPredicate:
    sub sp, sp, #0x170
    stp x19, x20, [sp, #0x120]
    stp x21, x22, [sp, #0x130]
    stp x23, x24, [sp, #0x140]
    stp x25, x26, [sp, #0x150]
    stp x29, x30, [sp, #0x160]
    add x29, sp, #0x160
    mov x19, x0
    mov w20, w1
    mov w21, w2
    mov w22, w3
    mov w23, w4
    mov x24, x5
    mov w25, w6

    mov x0, sp
    add x1, x19, #0x40
    mov x2, #0x4c
    bl _memcpy
    str w20, [sp, #0x4c]
    str w21, [sp, #0x50]
    str w22, [sp, #0x54]
    str w23, [sp, #0x58]
    add x0, sp, #0x60
    mov x1, x24
    mov x2, #176
    bl _memcpy
    str w25, [sp, #0x110]
    ldp x0, x1, [x19]
    ldp x2, x3, [x19, #16]
    ldp x4, x5, [x19, #32]
    ldp x6, x7, [x19, #48]
    adr x30, LrescueAppendPredicateAfter
    adrp x16, _rescueAppendPredicateAddress@PAGE
    ldr x16, [x16, _rescueAppendPredicateAddress@PAGEOFF]
    br x16

LrescueAppendPredicateAfter:
    ldp x19, x20, [sp, #0x120]
    ldp x21, x22, [sp, #0x130]
    ldp x23, x24, [sp, #0x140]
    ldp x25, x26, [sp, #0x150]
    ldp x29, x30, [sp, #0x160]
    add sp, sp, #0x170
    ret

.p2align 2
.globl _rescueInvokeAppendReturnPath
_rescueInvokeAppendReturnPath:
    sub sp, sp, #0x160
    stp x19, x20, [sp, #0x110]
    stp x21, x22, [sp, #0x120]
    stp x23, x24, [sp, #0x130]
    stp x29, x30, [sp, #0x150]
    add x29, sp, #0x150
    mov x19, x0
    mov w20, w1
    mov w21, w2
    mov w22, w3
    mov x23, x4
    mov w24, w5

    mov x0, sp
    add x1, x19, #0x40
    mov x2, #0x4c
    bl _memcpy
    str w20, [sp, #0x4c]
    str w21, [sp, #0x50]
    str w22, [sp, #0x54]
    add x0, sp, #0x58
    mov x1, x23
    mov x2, #176
    bl _memcpy
    str w24, [sp, #0x108]
    ldp x0, x1, [x19]
    ldp x2, x3, [x19, #16]
    ldp x4, x5, [x19, #32]
    ldp x6, x7, [x19, #48]
    adr x30, LrescueAppendReturnPathAfter
    adrp x16, _rescueAppendReturnPathAddress@PAGE
    ldr x16, [x16, _rescueAppendReturnPathAddress@PAGEOFF]
    br x16

LrescueAppendReturnPathAfter:
    ldp x19, x20, [sp, #0x110]
    ldp x21, x22, [sp, #0x120]
    ldp x23, x24, [sp, #0x130]
    ldp x29, x30, [sp, #0x150]
    add sp, sp, #0x160
    ret
