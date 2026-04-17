; ── Builder sigils ───────────────────────────────────────────────────────────
(builder_declaration
  "*" @keyword
  "builder" @keyword)

(builder_hook_declaration
  "*" @keyword)

(derived_declaration
  builder: (builder_application
    "*" @keyword))

(builder_declaration
  name: (type_identifier) @type.definition)

(builder_hook_declaration
  hook: [
    "expression"
    "block"
    "optional"
    "either"
    "array"
  ] @function.special)

(derived_declaration
  builder: (builder_application
    name: (type_identifier) @type))
