set shell := ["zsh", "-cu"]

default:
  @just --list

range-build:
  cd RangeCompiler && swift build --product range
