set shell := ["zsh", "-cu"]

default:
  @just --list

cli-build:
  cd CLI && swift build

range-compiler: cli-build
  CLI/.build/debug/CLI compile RangeCompiler
