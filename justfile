set shell := ["zsh", "-cu"]

default:
  @just --list

compiler-build:
  swift build --package-path RangeCompiler

compiler-test:
  swift build --package-path RangeCompiler --product range
  swift test --package-path RangeCompiler --filter RangeScriptTests

range-run:
  scripts/range run RangePlayground/Examples/LLVM/EmptyMain.range

check:
  bash -n scripts/range
  swift build --package-path RangeCompiler --product range
  swift test --package-path RangeCompiler --filter RangeScriptTests
  scripts/range check
