set shell := ["zsh", "-cu"]

default:
  @just --list

range-cli-build:
  cd RangeCLI && swift build

range-compiler: range-cli-build
  RangeCLI/.build/debug/RangeCLI run RangeCompiler
