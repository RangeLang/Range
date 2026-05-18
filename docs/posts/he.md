# Removing Initializers From Construct Semantics

Initializing constructs is always boring to write because most of the time you are just repeating the exact same fields back into the type. I removed init from the construction model entirely and made construct application bind directly to the declared shape.

## Before

neat id="h7v3ke" construct User {     let id: Int     let name: String      init(id: Int, name: String) {         self.id = id         self.name = name     } }  let user: User(id: 1, name: "George") 

## After

neat id="m4r8za" construct User {     let id: Int     let name: String }  let user: User(id: 1, name: "George") 

## Why

The old form worked, but it repeated the same fact twice.

1. I already declared id
2. I already declared name

The application should link directly to those declarations.
