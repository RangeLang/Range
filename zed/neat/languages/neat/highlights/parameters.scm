; ── Parameters & variables ───────────────────────────────────────────────────
(parameter
  name: (identifier) @variable.parameter)

(variable_declaration
  [
    "state"
    "environment"
    "binding"
    "value"
  ] @keyword
  name: (identifier) @variable)

(derived_declaration
  "derived" @keyword)

(member_declaration
  "var" @keyword
  name: (identifier) @property)
