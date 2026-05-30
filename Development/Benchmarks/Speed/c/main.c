#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    int64_t n = 10000000;
    if (argc > 1) {
        n = atoll(argv[1]);
    }

    int64_t i = 0;
    int64_t acc = 1;
    while (i < n) {
        acc = (acc * 1664525 + i) % 2147483647;
        i += 1;
    }

    printf("%" PRId64 "\n", acc);
    return 0;
}
