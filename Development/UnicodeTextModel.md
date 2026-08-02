# Unicode Text Model

This document defines the target semantic model for Range text. It is a design
contract for the Core and compiler migration; it does not claim that the
current byte-backed `String` runtime has already reached this model.

## Values

`UnicodeScalar` is one Unicode scalar value: an integer in the inclusive range
`0...0x10FFFF`, excluding the surrogate range `0xD800...0xDFFF`. It is not a
UTF-8 byte, a UTF-16 code unit, or a user-visible character.

```range
construct UnicodeScalar {
    let value: Int
}
```

The construct is valid only when `value` is a Unicode scalar value. Its
identity is its scalar value; it has no normalization, encoding, or grapheme
segmentation policy of its own.

`Character` is one independently addressable user-visible text element. It is
an ordered, nonempty sequence of `UnicodeScalar` values that forms one
extended grapheme cluster under the selected Unicode segmentation rules.

```range
construct Character {
    @many
    let scalars: UnicodeScalar
}
```

A single scalar such as `A` is a Character. A base letter plus a combining mark
is also one Character with multiple scalars. Emoji sequences may similarly be
one Character with several scalars. `Character` is the public grapheme value;
Range deliberately does not add a competing public `Grapheme` type.

`String` is an ordered sequence of `Character` values. Therefore:

- `String.count` means Character count, not UTF-8-byte count or scalar count.
- `String.characters` exposes the logical text relationship.
- Scalar traversal is explicit through a Character's `scalars` relationship.
- UTF-8 bytes are not a String's public semantic identity.

## Encoding boundary

`TextEncoding` describes transport and storage at an explicit boundary, not the
in-memory meaning of text. File I/O, process arguments, network payloads,
hashing bytes, and literal serialization select an encoding such as `.utf8`.
That boundary encodes or decodes between ordered Character values and code
units, and it rejects malformed byte sequences instead of silently creating
invalid scalars.

The current implementation is temporarily UTF-8 byte-backed. Its `String`
methods remain the supported authored API during the transition, but
`stringLength`, `stringByteAt`, and other raw operations are implementation
bridges, not the target text model.

## Required lowering before adoption

The compiler may not switch active String storage to Characters until it can
lower an ordered `@many` relationship of aggregate elements with stable
ordinal, stride, initialization, move, destruction, indexing, and mutation.
That includes `Buffer<UnicodeScalar>`, `Buffer<Character>`, and nested owned
storage. Until then, Core's `UnicodeScalar` and `Character` declarations are
intentional semantic targets rather than proof of executable Unicode text.
