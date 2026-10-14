# AGENTS.md: risk-rules

## Purpose

risk-rules is a provider-neutral library for transaction monitoring and fraud control on outgoing
transfers and card authorisations. Rules are named checks with a severity and a stable reason code;
the engine runs every rule, keeps every hit with its evidence and takes the worst severity. It is
pure, synchronous and does no I/O except reading a policy file.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `risk_rules` library: contexts, features, rules, engine, decisions, policy, reason codes, review queue |
| `bin/` | The `risk-rules` CLI: `check-policy`, `evaluate`, `features`, `reason-codes` |
| `examples/` | A policy and two contexts (card, transfer) used by the CLI and by a test |
| `test/` | Expect tests per rule group, policy and example tests, Quickcheck properties, and `fixtures.ml` |
| `.github/` | `ci.yml` |
| `README.md` | Modules, built-in rules, explainability, policy format, CLI, stable types |

## Build, test, docs

Run from the repository root, inside the workspace (`..` is the workspace root):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @risk-rules/all
opam exec --switch 5.2.0+ox -- dune build --root .. @risk-rules/runtest
```

For parallel work, set `DUNE_BUILD_DIR=_build-risk-rules-<task>` (resolved from the workspace
root, because of `--root ..`).

Standalone (outside the workspace): add the organisation opam repository
(`opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`),
install the dependencies with `opam install --deps-only .`, then `dune build @all @runtest`.

CLI, from the repository root:

```sh
dune exec --root .. ./risk-rules/bin/main.exe -- check-policy -policy examples/policy.sexp
```

## Conventions

- Format only this repository: `dune build --root .. @risk-rules/fmt --auto-promote`. Never run
  `dune fmt` at the workspace root.
- Every module has an `.mli`. Use labelled arguments, `open! Core`, `ppx_jane` and `ppx_yojson_conv`.
- Stable types: `Severity`, `Reason_code`, `Typology`, `Hit`, `Decision`, `Tier`, `Country`, `Mcc`,
  `Context`, `Features`, `Review_queue` carry `Stable.V1` bin_io types whose digests are pinned in
  the expect tests. Do not change a pinned shape without deciding that on purpose.
- Rules are generic in their context (`'ctx Rule.t`). Add the domain rule where the context is
  defined, and test the engine with plain values first.
- Every public value has odoc. Add a `CHANGES.md` entry for user-visible changes once the file exists.
- Customer messages for suspicion typologies are deliberately neutral. Change their wording deliberately,
  in its own commit that says why.
- Comments for humans: where a test pins a value that depends on the platform or on a library quirk,
  say why at that place.

## Dependencies and dependents

risk-rules depends on `money` (amounts, currencies), `payments-core` (transfer drafts, beneficiaries,
trust, travel-rule records and SCA exemptions), `zarith` and `yojson`. Its tests also use `ledger`.
CI pins `fixed-decimal`, `money`, `ledger` and `payments-core` from GitHub in that order.
Dependents: `../risk-models` (the `Risk_rules.Model.S` adapter and the feature contract), and the
API layer, card authoriser, back-tests and model training that share these rules.

## CI

`.github/workflows/ci.yml` runs the `ox-setup` composite action from `winterchill-trading/infra`
with the pins above, then `dune build` and `dune test`, plus the `obj-magic` reusable workflow.
To check a run, use `gh run list --limit 1`, and at most one `gh run watch <id> --exit-status`.
Do not poll in a loop.

## Pitfalls

- A sibling under active development can break the shared workspace build for minutes. Build
  against the pushed commits, since CI does, and check CI after you bind to a new sibling type.
- Expect output that names a temporary directory: replace the path inside the sexp atoms before
  printing, because line wrapping depends on the path length, and it differs between macOS and Linux.
- To mutation-check a Quickcheck property, disable the rule with `false && ...`, and add `ignore x;`
  in the mutant or the dev profile fails on warning 26 before any test runs.
- `Decision.t` is private: its severity is re-derived from its hits when read. Build decisions only
  through `Engine.evaluate`.
- `Context.Stable.V1` embeds payments-core's stable types, so its digest moves when they move. That
  test failing is the signal to re-check journaled contexts, not a reason to re-pin silently.
- `include Int` in a module that defines its own `Stable` fails; constrain with
  `include (Int : Identifiable.S with type t = int)`.

## Where to read more

- `README.md` (modules, built-in rules, explainability, policy format, CLI).
- `examples/policy.sexp` for the policy syntax.
- `../specs/repos/risk-rules.md` for the repository summary.
- `../oxcaml-claude-skills/AGENTS.md` (workspace guide) and the skills
  `../oxcaml-claude-skills/skills/banking-standards/` (decision and audit rules) and
  `../oxcaml-claude-skills/skills/janestreet-ocaml-style/`.
- `../oxcaml-claude-skills/GOTCHAS.md` (the risk-rules entries of the workspace-wide log).

## Never do

- Install an opam package that changes the compiler, `core`, `base`, `async` or `ppx_jane` on the
  shared `5.2.0+ox` switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
- Add I/O to the library beyond reading a policy file, or read the wall clock inside a rule.
- Publish, tag or release.
- Commit real customer data or credentials; fixtures are built from library values.
