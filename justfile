set shell := ["zsh", "-cu"]

default:
  @just --list

rangec-build:
  cd RangeCompiler && swift build --product rangec
