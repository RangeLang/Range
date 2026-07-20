set shell := ["zsh", "-cu"]

default:
  @just --list

compiler-build:
  scripts/range compiler next

compiler-test:
  scripts/range compiler progression

candidate:
  scripts/range check-compiler-candidate

check:
  bash -n scripts/range scripts/range-native scripts/check-range-compiler-candidate scripts/verify-range-compiler-seed
  scripts/range check-stage2-compiler
  scripts/range compiler progression
