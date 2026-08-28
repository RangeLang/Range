# RangeView Metal boundary

Metal, AppKit, QuartzCore, and the Objective-C runtime are operating-system ABI
boundaries used by ordinary Range code. They are not RangeView renderers,
compiler backends, runtime adapters, or source-level dispatch identities.

`Metal.range` begins the ordinary `@extern` declaration surface. Compiler B
must lower those declarations and their typed Range call sites through its
general LLVM emission path. Additional `objc_msgSend` call shapes belong to
that general foreign-call representation; they must not become C wrappers or
`@metal(kind:)` cases.

The previous Compiler B `RangeViewMetal` entry and its concatenated fixture
route were deleted. Until Compiler B composes project source revisions and
lowers these calls generally, RangeView is intentionally not claimed as a
working native application.
