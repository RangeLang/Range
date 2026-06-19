; Hand-written by-hand spike: this is EXACTLY the text that an `@llvm`-annotated
; Int construct would eventually emit. No Swift in the path. Compiled + run by clang.
;
; Modeling:
;   @llvm { i$bits }                  -> Int<bits> lowers to i<bits>   (here: i64)
;   function +(lhs,rhs): Self         -> @llvm { %r = add  $lhs.type $lhs, $rhs }
;   function /(lhs,rhs): Self  signed -> @llvm { %r = sdiv $lhs.type $lhs, $rhs }
;   function /(lhs,rhs): Self  unsign -> @llvm { %r = udiv $lhs.type $lhs, $rhs }
;
; The point: `add`, `sdiv`, `udiv`, `i64` are text. Range macros would author this
; text; clang turns it into a running executable.

target triple = "arm64-apple-darwin"

; Int<64, .signed> + : add is signedness-independent
define i64 @range_int_add(i64 %lhs, i64 %rhs) {
entry:
  %r = add i64 %lhs, %rhs
  ret i64 %r
}

; Int<64, .signed> / : signed division -> sdiv
define i64 @range_int_sdiv(i64 %lhs, i64 %rhs) {
entry:
  %r = sdiv i64 %lhs, %rhs
  ret i64 %r
}

; Int<64, .unsigned> / : unsigned division -> udiv
define i64 @range_int_udiv(i64 %lhs, i64 %rhs) {
entry:
  %r = udiv i64 %lhs, %rhs
  ret i64 %r
}
