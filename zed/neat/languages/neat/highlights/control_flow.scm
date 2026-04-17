[
  "if"
  "else"
  "for"
  "in"
  "while"
  "switch"
  "case"
  "default"
] @keyword

(break_statement) @keyword.control
(continue_statement) @keyword.control
(return_statement
  "return" @keyword.control)

(switch_statement
  "switch" @keyword)

(switch_case
  "case" @keyword)

(switch_default
  "default" @keyword)
