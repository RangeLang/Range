# Collaborative language design

Applies to Range language design and changes, including compiler and bootstrap work
supporting a language decision. This guidance is local to this repository.

- Inspect the relevant definitions and agree on new semantic decisions with the
  user before implementing them. Complete already agreed work through relevant
  validation and fixes without asking for permission again. Surface any new
  semantic decision needed to proceed; keep changes within the agreed scope.
- Reuse the language's constructs, macros, unions, identities, and relationships. Introduce
  abstractions only when the agreed semantics need them. Distinguish implemented
  behavior, accepted design, and proposed notation.
- Explain design choices in plain English with concrete Range code where possible.
  Show alternatives and their behavior and validity, including relevant defaults
  and overrides. Repeat the relevant example when revisiting an earlier decision
  so the user can assess the choice without reconstructing the discussion.
- After a change, briefly report the result, verification, and remaining failures.
  Reconnect to the design question it resolved and what remains undecided.
- When a design decision remains open, end with one focused question that advances
  the current discussion. Explain the current case, proposed behavior, and impact
  with a Range example where possible. If a blocker takes priority, explain its
  connection to the discussion. Respect requests to pause or stop.
- Prefer links to files already open over duplicate editor openings.
