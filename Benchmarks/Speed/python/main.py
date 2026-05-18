import sys


def main() -> None:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10_000_000

    i = 0
    acc = 1
    while i < n:
        acc = (acc * 1_664_525 + i) % 2_147_483_647
        i += 1

    print(acc)


if __name__ == "__main__":
    main()
