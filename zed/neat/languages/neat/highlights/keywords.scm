("@" @keyword)

; When syntax is incomplete, tree-sitter can fall back to plain identifiers
; inside ERROR nodes. Keep core keywords colored by text anyway.
((identifier) @keyword
 (#match? @keyword "^(construct|enum|case|extension|macro|func|function|protocol|state|environment|binding|derived|value|var|if|else|for|in|while|switch|default|return|break|continue|background|get|set|on|builder|capture|precedencegroup|prefix|infix|postfix|operator)$"))

((identifier) @keyword
 (#match? @keyword "^(core|main)$"))

[
  "background"
  "binding"
  "break"
  "builder"
  "capture"
  "case"
  "construct"
  "continue"
  "default"
  "derived"
  "else"
  "enum"
  "environment"
  "extension"
  "for"
  "func"
  "function"
  "get"
  "if"
  "in"
  "infix"
  "macro"
  "main"
  "on"
  "operator"
  "postfix"
  "precedencegroup"
  "prefix"
  "protocol"
  "return"
  "set"
  "state"
  "switch"
  "value"
  "var"
  "while"
] @keyword
