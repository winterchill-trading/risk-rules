# AGENTS.md: examples/

`policy.sexp` (the policy format), `context-card.sexp` and `context-transfer.sexp` (inputs for the
CLI's `evaluate`).

- The test stanza reads these files, so they must parse with the current library. Update them in the
  same commit as a format change.
- They are documentation as well as test input; keep them small.
