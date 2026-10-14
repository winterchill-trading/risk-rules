# AGENTS.md: lib/

The `risk_rules` library. Each module has an `.mli`; change it first and keep it documented.

- `severity.ml`, `reason_code.ml`, `typology.ml`, `hit.ml`, `decision.ml`: the outcome types. Stable.
- `rule.ml`, `rules.ml`, `rule_spec.ml`: rules, the built-in rules, and the sexp form of built-in rules.
  `Rule.cap` puts a rule into shadow mode (it records hits but changes no decision).
- `engine.ml`: `evaluate` runs every rule. A rule that raises becomes a `RULE_ERROR` block.
- `context.ml`: what the rules see (tier, balances, payments-core draft, history, geo, session).
- `features.ml`, `model.ml`: the single feature definition and the `Model.S` interface for scores.
- `policy.ml`, `limits.ml`, `tier.ml`, `country.ml`, `mcc.ml`: policy loading and validated identifiers.
- `sca_outcome.ml`, `review_queue.ml`: the SCA verdict for payments-core, and the immutable review queue.

A new rule needs its reason code, typology and a test that checks the evidence.
