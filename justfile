set shell := ["zsh", "-cu"]

default:
  @just --list

compiler-build:
  scripts/range compiler next

compiler-test:
  scripts/range compiler progression

compiler-build-cached:
  scripts/range compiler next --cached-only

compiler-test-cached:
  scripts/range compiler progression --cached-only

candidate:
  scripts/range check-compiler-candidate

check:
  bash -n scripts/range scripts/range-native scripts/resolve-range-compiler-build scripts/check-range-value-ownership scripts/check-range-compiler-cache scripts/check-range-compiler-candidate scripts/verify-range-compiler
  scripts/range check-compiler-integrity
  scripts/range check-compiler-candidate

check-fast:
  bash -n scripts/range scripts/range-native scripts/resolve-range-compiler-build scripts/check-range-value-ownership scripts/check-range-unsigned8 scripts/check-range-float-widths scripts/check-range-compiler-cache scripts/check-range-compiler-candidate scripts/verify-range-compiler
  scripts/check-range-unsigned8
  scripts/check-range-float-widths
  scripts/check-range-compiler-cache
  scripts/range check-compiler-integrity

check-unsigned8 candidate="":
  scripts/check-range-unsigned8 {{candidate}}

check-float-widths candidate="":
  scripts/check-range-float-widths {{candidate}}
