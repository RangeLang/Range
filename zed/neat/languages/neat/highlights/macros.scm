(macro_declaration
  "macro" @keyword)

(macro_bindings
  "in" @keyword)

(macro_application
  sigil: "#" @type
  name: (identifier) @type)

(macro_declaration
  name: (identifier) @function.special)

(macro_declaration
  target: (macro_target
    type: (_) @type))

(macro_declaration
  "->" @operator
  expansion_type: (_) @type)
