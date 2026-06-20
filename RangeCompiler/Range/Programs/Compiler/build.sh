#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/range"
IR_FILE="$BUILD_DIR/RangeScalar.ll"
SCALARS_FILE="$BUILD_DIR/scalars.txt"
EXECUTABLE="$BUILD_DIR/Compiler"
BUILD_SOURCE="$SCRIPT_DIR/Build.range"

mkdir -p "$BUILD_DIR"

range_string_function() {
    local name="$1"
    perl -0 -e '
        my ($name, $file) = @ARGV;
        open my $fh, "<", $file or exit 1;
        local $/;
        my $source = <$fh>;
        if ($source =~ /function\s+\Q$name\E\(\):\s+String\s*\{\s*return\s+"((?:\\.|[^"\\])*)"/s) {
            my $s = $1;
            $s =~ s/\\n/\n/g;
            $s =~ s/\\"/"/g;
            $s =~ s/\\\\/\\/g;
            print $s;
            exit 0;
        }
        exit 1;
    ' "$name" "$BUILD_SOURCE"
}

main_count="$(
    find "$SCRIPT_DIR" -name '*.range' -type f | sort | while read -r file; do
        perl -0ne 'while (/\@main\s*\{/g) { print "main\n" }' "$file"
    done | wc -l | tr -d ' '
)"

if [[ "$main_count" == "0" ]]; then
    printf '%s\n' "$(range_string_function missingMainMessage)" >&2
    exit 1
fi

if [[ "$main_count" != "1" ]]; then
    printf '%s\n' "$(range_string_function duplicateMainMessage)" >&2
    exit 1
fi

{
    printf '# Range scalar build file\n'
    find "$ROOT_DIR/RangeCompiler/Range/Core/DataSystem" -name '*.range' -type f | sort | while read -r file; do
        name="$(basename "$file" .range)"
        if perl -0ne 'exit(/\@integer\s*\n\s*construct/ ? 0 : 1)' "$file"; then
            printf 'scalar\tinteger\t%s\t%s\n' "$name" "$file"
        fi
        if perl -0ne 'exit(/\@bool\s*\n\s*construct/ ? 0 : 1)' "$file"; then
            printf 'scalar\tbool\t%s\t%s\n' "$name" "$file"
        fi
        if perl -0ne 'exit(/\@boolean\s*\n\s*construct/ ? 0 : 1)' "$file"; then
            printf 'scalar\tboolean\t%s\t%s\n' "$name" "$file"
        fi
        if perl -0ne 'exit(/\@float\s*\n\s*construct/ ? 0 : 1)' "$file"; then
            printf 'scalar\tfloat\t%s\t%s\n' "$name" "$file"
        fi
    done
} > "$SCALARS_FILE"

perl -0ne '
    if (/open\s+macro\s+main\(\):\s*\@block\s*\{.*?let\s+llvm:\s+String\("((?:\\.|[^"\\])*)"\)/s) {
        my $s = $1;
        $s =~ s/\\n/\n/g;
        $s =~ s/\\"/"/g;
        $s =~ s/\\\\/\\/g;
        print $s;
        exit 0;
    }
    exit 1;
' "$ROOT_DIR/RangeCompiler/Range/Foundation/Macros/Main.range" > "$IR_FILE"

clang "$IR_FILE" -o "$EXECUTABLE"

printf '%s\n' "$(range_string_function buildSuccessMessage)"
printf '%s\n' "$IR_FILE"
printf '%s\n' "$EXECUTABLE"
