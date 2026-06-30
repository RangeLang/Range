set shell := ["zsh", "-cu"]

default:
  @just --list

rangec-build:
  cd RangeCompiler && swift build --product rangec

range-compiler: rangec-build
  scripts/range emit-llvm RangeCompiler/Range/Programs/Compiler/Main.range RangeCompiler/Range/Programs/Compiler/.range/Build/llvm/Main.ll
