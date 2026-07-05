set shell := ["zsh", "-cu"]

default:
  @just --list

compiler-build:
  swift build --package-path RangeCompiler

range-run:
  scripts/range run RangePlayground/Examples/LLVM/EmptyMain.range
