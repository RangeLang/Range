#include <stdio.h>
#include <stdint.h>

// These come from the hand-written LLVM IR (int_ops.ll).
int64_t range_int_add(int64_t lhs, int64_t rhs);
int64_t range_int_sdiv(int64_t lhs, int64_t rhs);
int64_t range_int_udiv(int64_t lhs, int64_t rhs);

int main(void) {
    int64_t add = range_int_add(40, 2);          // expect 42
    int64_t sdiv = range_int_sdiv(-20, 5);        // signed: expect -4
    int64_t udiv = (int64_t)range_int_udiv(20, 5); // unsigned: expect 4

    printf("add(40,2)   = %lld (expect 42)\n", (long long)add);
    printf("sdiv(-20,5) = %lld (expect -4)\n", (long long)sdiv);
    printf("udiv(20,5)  = %lld (expect 4)\n", (long long)udiv);

    int ok = (add == 42) && (sdiv == -4) && (udiv == 4);
    printf("%s\n", ok ? "PASS: Range->LLVM->native ran with no Swift in the path" : "FAIL");
    return ok ? 0 : 1;
}
