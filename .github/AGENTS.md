# AGENTS.md: .github/

`workflows/ci.yml`, the only workflow of this repository.

- The `ox-setup` pins must list the sibling repositories in dependency order (fixed-decimal, money,
  ledger, payments-core) and match `risk-rules.opam`.
- Check runs with `gh run list --limit 1`; at most one `gh run watch <id> --exit-status`. No loops.
