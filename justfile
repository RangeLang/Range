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
  bash -n scripts/range scripts/range-native scripts/check-range-compiler-cache scripts/check-range-compiler-candidate scripts/verify-range-compiler-seed
  scripts/range check-stage2-compiler
  scripts/range compiler progression

check-fast:
  bash -n scripts/range scripts/range-native scripts/check-range-unsigned8 scripts/check-range-compiler-cache scripts/check-range-compiler-candidate scripts/verify-range-compiler-seed
  scripts/check-range-unsigned8
  scripts/check-range-compiler-cache
  scripts/range check-seed-integrity

check-unsigned8 candidate="":
  scripts/check-range-unsigned8 {{candidate}}
