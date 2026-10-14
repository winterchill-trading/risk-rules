# AGENTS.md: test/

Inline tests (ppx_expect and Quickcheck). The test stanza depends on `../examples/*.sexp`, so an
example that stops parsing fails the build.

- `fixtures.ml` builds contexts from payments-core and money values. Add fixtures there, not inline.
- `test_rules_*.ml` cover one rule group each (behaviour, caps, card, research, typologies).
- `test_properties.ml` holds the Quickcheck properties: adding a rule never lowers a decision or drops
  a hit, and logistic scores stay in [0, 1].
- Pinned `Stable.V1` digests are asserted in the expect tests that the README stable-types section lists.
- Promote expect output with `dune promote` after reading the diff.
