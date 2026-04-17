; ── Declarations ─────────────────────────────────────────────────────────────
(sigiled_declaration
  "construct" @keyword)

(protocol_declaration
  "protocol" @keyword)

((identifier) @function.method
 (#eq? @function.method "init"))

(enum_declaration
  "enum" @keyword)

(extension_declaration
  "extension" @keyword)

(callable_declaration
  "function" @keyword)

(function_declaration
  "func" @keyword)
