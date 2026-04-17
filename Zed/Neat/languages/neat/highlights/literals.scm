; ── Literals ─────────────────────────────────────────────────────────────────
(string_literal
  "\"" @string)
(string_content) @string
(escape_sequence) @string.escape
(interpolation
  "\\(" @string.escape
  ")" @string.escape)
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean
(nil_literal) @keyword
