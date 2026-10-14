# AGENTS.md: bin/

The `risk-rules` command (`main.ml`): `check-policy`, `evaluate`, `features`, `reason-codes`.

- `evaluate` exits 0 on allow, 5 on challenge, 10 on review, 20 on block, and 2 on a usage or parse
  error. Scripts depend on these codes; changing one is a breaking change.
- `evaluate` accepts `-constant-model NAME=VALUE` for trying a model score without a model file.
- No network, no credentials and no environment variables are read.
