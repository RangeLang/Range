; ── Parameters & variables ───────────────────────────────────────────────────
(parameter
  name: (identifier) @variable.parameter)

(parameter
  type: (capture_type
    "capture" @keyword
    captured: (_) @type))

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
