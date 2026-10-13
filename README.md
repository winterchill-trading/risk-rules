# risk-rules

Provider-neutral rule engine for outgoing transfers and card authorisations.
Rules are named predicates with a severity (`Allow < Review < Block`); the
engine runs every rule, lists every hit and keeps the worst severity. A
policy maps customer tiers to rule sets and loads from a sexp file. Items
that need a person go to an immutable review queue. Pure OCaml, no Async, no
I/O except reading a policy file.

## Why separate

Risk decisions change on a different clock from payment plumbing: limits,
country lists and merchant categories are edited by operators, reviewed by
compliance and replayed during audits. Keeping the rules in their own
library over plain values (`Context.t` in, `Decision.t` out) means a decision
can be reproduced from a logged context, a policy change can be tested
without a provider or a database, and the API layer, the card authoriser and
offline back-tests all share one implementation. It depends only on `money`
(amounts, currencies) and `payments-core` (transfer drafts, beneficiaries,
rails).

## Usage

```ocaml
open! Core
open Risk_rules

let policy = Policy.load "policy.sexp" |> Or_error.ok_exn

let decide ~draft ~tier ~history ~now =
  let transfer = Context.Transfer.create draft |> Or_error.ok_exn in
  let ctx =
    { Context.customer = "cust-1"
    ; tier
    ; now
    ; balances = []
    ; subject = Transfer transfer
    ; history = List.filter_map history ~f:Context.Past_transfer.of_transfer
    ; geo = Context.Geo.unknown
    }
  in
  match Policy.evaluate policy ctx with
  | { severity = Allow; _ } -> `Send
  | { severity = Review; _ } as decision -> `Hold decision (* Review_queue.submit *)
  | { severity = Block; _ } as decision -> `Refuse decision
;;
```

Rules can also be built in code, and any `'ctx Rule.t` works with
`Engine.evaluate`:

```ocaml
let rules =
  [ Rules.per_transfer_cap (Limits.create_exn [ Money.Amount.of_string "1000.00 EUR" ])
  ; Rules.velocity ~max_count:5 ~window:(Time_ns.Span.of_min 10.) ()
  ; Rules.online_toggle ()
  ]
in
Engine.evaluate rules ctx
```

## Modules

| Module | What it is |
|--------|------------|
| `Severity` | `Allow < Review < Block`, `worst` |
| `Rule` | `'ctx Rule.t`: name, severity, predicate returning a reason |
| `Hit`, `Decision` | one triggered rule; worst severity plus every hit (bin_io, sexp) |
| `Engine` | `evaluate : 'ctx Rule.t list -> 'ctx -> Decision.t`; a raising rule becomes a `Block` hit |
| `Context` | what rules see: tier, balances, the payments-core draft and beneficiary, wallet facts, past transfers, card authorisation, time, geo |
| `Limits` | one threshold per currency; a missing currency is a limit of zero |
| `Rules` | built-in rules (table below) |
| `Rule_spec`, `Policy` | built-in rules as sexp data; tier to rule set table |
| `Review_queue` | immutable queue of held operations with `decide` and `annotate` |
| `Tier`, `Country`, `Mcc` | validated identifiers |

## Built-in rules

| Rule (`Rule_spec`) | Triggers when | Default |
|--------------------|---------------|---------|
| `Per_transfer_cap` | the transfer alone is above the limit | Block |
| `Daily_cap`, `Monthly_cap`, `Window_cap` | transfer plus same-currency transfers in a rolling 24 h / 30 d / custom window are above the limit | Block |
| `Velocity` | more than N transfers (this one included) within M | Review |
| `New_beneficiary_cooldown` | above X to a beneficiary first seen less than Y ago (trusted ones exempt only with `exempt_trusted`) | Block |
| `Structuring` | this transfer is a round multiple or just below a threshold and at least N such transfers fall in the window | Review |
| `Blocked_countries` / `High_risk_countries` | beneficiary or merchant country, or request IP country, is listed | Block / Review |
| `Unverified_self_hosted_wallet` | above X to a self-hosted wallet without proof of ownership (travel-rule hook) | Review |
| `Blocked_mccs` | the card merchant category is listed | Block |
| `Online_toggle` | online card payment while the cardholder switched online payments off | Block |
| `Manual_review` | always (park a tier under investigation) | Review |
| `(Severity S spec)` | wraps any spec to override its severity | |

Fail-closed choices: a currency missing from a cap's limits is capped at
zero; a tier missing from the policy is a `Block`; a rule that raises is a
`Block`. `Structuring` is the exception: a currency without a threshold or
round unit never matches, because flagging every amount would bury real
cases.

Windows are rolling, not calendar periods, so no time zone is involved and a
limit cannot be doubled across a day or month boundary. Past transfers count
from the moment they are created while awaiting authentication, submitted,
pending or settled; drafts, failed, cancelled and returned transfers do not.

## Policy files

See [`examples/policy.sexp`](examples/policy.sexp). Amounts are written as
`"<decimal> <currency>"` with the currency's full number of fractional digits
(`"0.00500000 BTC"`, `"100.000000 USDC"`); spans as `10m`, `24h`, `3d`.
Policies are validated on load: duplicate tiers, duplicate currencies in one
limit list, negative limits, non-positive windows and counts are refused.

## CLI

```
risk-rules check-policy -policy examples/policy.sexp
risk-rules evaluate -policy examples/policy.sexp examples/context-card.sexp
risk-rules evaluate -sexp -policy examples/policy.sexp examples/context-transfer.sexp
```

`evaluate` exits 0 on allow, 10 on review, 20 on block and 2 on a usage or
parse error, so scripts can branch on the outcome.

## Stable types and tests

`Severity`, `Hit`, `Decision`, `Tier`, `Country`, `Mcc`, `Context` and
`Review_queue` have `Stable.V1` bin_io types with their digests pinned in the
expect tests. `Decision.t` is private and re-derives its severity from its
hits on read. Tests: expect tests per rule, policy loading and refusals, the
example files, and Quickcheck properties that adding a rule (generic or
built-in) never lowers a decision and never drops a hit.

Everything is verified on fixtures; there is no external service. There is
no `.env`: the library never needs credentials.

## Build

```
dune build @all @runtest
```

CI pins `fixed-decimal`, `money`, `ledger` and `payments-core` from GitHub in
that order.

## Known gaps

- Caps compare amounts in the transfer's own currency only; there is no FX
  conversion, so a customer splitting a limit across EUR and USDC is checked
  per currency.
- Card authorisations are not counted in transfer caps or velocity; card
  spend limits belong to the card library.
- `Context` fields come from the caller; the library does not check that the
  history really belongs to the customer or that `now` is current.
