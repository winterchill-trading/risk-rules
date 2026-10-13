# risk-rules

Provider-neutral transaction monitoring and fraud control for outgoing
transfers and card authorisations. Rules are named checks with a severity
(`Allow < Challenge < Review < Block`) and a stable reason code; the engine
runs every rule, keeps every hit with its evidence and takes the worst
severity. Rules cover limits, the standard typologies (structuring, money
mules, account takeover, authorised push payment scams, card testing),
sanctions geography, the crypto travel rule, model scores and PSD2 strong
customer authentication exemptions. A policy maps customer tiers to rule
sets and loads from a sexp file; items for operators go to an immutable
review queue. Pure OCaml, synchronous, no I/O except reading a policy file.

## Why separate

Risk decisions change on a different clock from payment plumbing: limits,
country lists and thresholds are edited by operators, reviewed by
compliance and replayed during audits and model training. Keeping the rules
in their own library over plain values (`Context.t` in, `Decision.t` out)
means a decision can be reproduced from a journaled context, a policy
change can be tested without a provider or a database, and the API layer,
the card authoriser, offline back-tests and the model training pipeline
share one implementation of every rule and every feature. It depends only
on `money` (amounts, currencies) and `payments-core` (transfer drafts,
beneficiaries with trust, first use and payee check, travel-rule records).

## Usage

```ocaml
open! Core
open Risk_rules

let policy = Policy.load "policy.sexp" |> Or_error.ok_exn

let decide ~models ~draft ~tier ~outgoing ~incoming ~session ~now =
  let transfer = Context.Transfer.create draft |> Or_error.ok_exn in
  let ctx =
    { Context.customer = "cust-1"
    ; tier
    ; now
    ; balances = []
    ; subject = Transfer transfer
    ; history = List.filter_map outgoing ~f:Context.Past_transfer.of_transfer
    ; incoming = List.filter_map incoming ~f:(fun t -> Context.Past_transfer.of_incoming t)
    ; card_history = []
    ; geo = Context.Geo.unknown
    ; session
    }
  in
  let decision = Policy.evaluate ~models policy ctx in
  (* Journal [ctx] and [decision] together: both are bin_io and sexp. *)
  match decision.severity with
  | Allow -> `Send
  | Challenge -> `Ask_for_sca (Decision.customer_message decision)
  | Review -> `Hold decision (* Review_queue.submit *)
  | Block -> `Refuse (Decision.customer_message decision)
;;
```

Rules can also be built in code; any `'ctx Rule.t` works with
`Engine.evaluate`:

```ocaml
Engine.evaluate
  [ Rules.per_transfer_cap (Limits.create_exn [ Money.Amount.of_string "1000.00 EUR" ])
  ; Rules.velocity ~max_count:5 ~window:(Time_ns.Span.of_min 10.) ()
  ; Rules.model_score my_model { challenge_at = Some 0.5; review_at = Some 0.8; block_at = None }
  ]
  ctx
```

## Modules

| Module | What it is |
|--------|------------|
| `Severity` | `Allow < Challenge < Review < Block`; `Challenge` means a strong authentication step-up |
| `Reason_code`, `Typology` | stable codes (`LIMIT_DAILY`, `MULE_FAN_IN`, ...) with typology, operator description and customer message |
| `Rule` | `'ctx Rule.t`: fixed or graded outcomes; `cap` for shadow mode |
| `Hit`, `Decision` | rule, severity, code, typology, detailed reason, evidence; worst severity plus every hit; `reason_codes`, `customer_message` |
| `Engine` | `evaluate : 'ctx Rule.t list -> 'ctx -> Decision.t`; a raising rule becomes a `RULE_ERROR` block |
| `Context` | what rules see: tier, balances, the payments-core draft and beneficiary, wallet facts from the travel-rule record, outgoing and incoming history, card history, geo, session (device, credential change, account age, failed SCA) |
| `Features` | the single feature definition: typed record, `of_context`, schema, numeric vector, JSON export |
| `Model` | `Model.S`: `Features.t -> Score.t` (value in [0, 1] with reason codes), pure and synchronous; `logistic` baseline, `constant` |
| `Limits` | one threshold per currency; a missing currency is a limit of zero |
| `Rules` | built-in rules (table below) |
| `Rule_spec`, `Policy` | built-in rules as sexp data; tier to rule set table; models looked up by name |
| `Sca_outcome` | a decision's SCA verdict as `Required`, `Exempt of Payments_core.Sca.Exemption.t` or `Not_assessed`, ready for `Transfer.require_sca` / `Transfer.exempt` |
| `Review_queue` | immutable queue of held operations with `decide` and `annotate` |
| `Tier`, `Country`, `Mcc` | validated identifiers |

## Built-in rules

| `Rule_spec` | Code | Triggers when | Default |
|-------------|------|---------------|---------|
| `Per_transfer_cap` | `LIMIT_PER_TRANSFER` | the transfer alone is above the limit | Block |
| `Daily_cap`, `Monthly_cap`, `Window_cap` | `LIMIT_DAILY`, ... | transfer plus same-currency transfers in a rolling 24 h / 30 d / custom window are above the limit | Block |
| `Velocity` | `VELOCITY_OUT` | more than N transfers (this one included) within M | Review |
| `Structuring` | `STRUCTURING` | this transfer is a round multiple or just below a threshold and at least N such fall in the window | Review |
| `Mule_pass_through` | `MULE_PASS_THROUGH` | outgoing in the window reaches 80% of what came in | Review |
| `Mule_fan_in` | `MULE_FAN_IN` | N or more distinct payers into a young account | Review |
| `New_account_payout` | `NEW_ACCOUNT_PAYOUT` | above X from an account younger than Y | Review |
| `New_beneficiary_cooldown` | `NEW_BENEFICIARY_COOLDOWN` | above X to a beneficiary first used less than Y ago | Block |
| `Account_takeover` | `ACCOUNT_TAKEOVER_SIGNALS` | N of: new device, IP outside residence, recent credential change, failed SCA, new beneficiary, large share of balance | Review |
| `App_fraud` | `APP_NEW_BENEFICIARY_BALANCE` | most of the balance to a new beneficiary | Review |
| `App_first_large_payment` | `APP_FIRST_LARGE_PAYMENT` | over 5x the 30-day mean to a new beneficiary | Review |
| `Vop_not_matched` | `VOP_NOT_MATCHED` | verification of payee says no match or close match | Review |
| `Blocked_countries` / `High_risk_countries` | `GEO_BLOCKED` / `GEO_HIGH_RISK` | beneficiary, merchant or request IP country is listed | Block / Review |
| `Unverified_self_hosted_wallet` | `TRAVEL_RULE_SELF_HOSTED` | above X to a self-hosted wallet without proof of ownership | Review |
| `Blocked_mccs`, `Online_toggle`, `Card_testing` | `CARD_*` | merchant category listed; online payment while switched off; many small or declined authorisations | Block |
| `Score` | `SCORE_HIGH` | the named model's score crosses the challenge, review or block threshold | graded |
| `Sca_tra` | `SCA_REQUIRED` / `SCA_EXEMPT` | remote payment without an exemption (trusted beneficiary, or TRA within the RTS annex band for the observed fraud rate with no takeover signal and a low score); crypto payouts are never exempt; exemptions are recorded as allow hits | Challenge |
| `Manual_review` | `MANUAL_REVIEW` | always (park a tier under investigation) | Review |
| `(Severity S spec)` | | overrides (caps, for graded rules) the severity | |
| `(Shadow spec)` | | runs the spec with hits capped at Allow: logged, no effect | |

Fail-closed choices: a currency missing from a cap's limits is capped at
zero; a tier missing from the policy is a `Block` (`UNKNOWN_TIER`); a rule
that raises is a `Block` (`RULE_ERROR`); a model named by the policy but not
loaded is a `Review` (`SCORE_UNAVAILABLE`). `Structuring` is the exception:
a currency without a threshold or round unit never matches, because
flagging every amount would bury real cases.

Windows are rolling, not calendar periods. Past transfers count from the
moment they are created while awaiting authentication, submitted, pending,
settled or under recall; drafts, failed, rejected, cancelled and returned
transfers do not.

## Explainability

Every hit carries a stable reason code, its typology, a detailed reason for
operators and the audit log, and evidence: the values the rule compared
(`limit=1000.00 EUR`, `signal=new_device`, `model_version=...`,
`model_reason=amount_to_balance=2.85`). `Decision.reason_codes` lists the
codes most severe first; `Decision.customer_message` gives text for the
customer from the deciding code. Messages for suspicion typologies (mules,
structuring, takeover, scores) are deliberately neutral to avoid tipping
off; push payment scam codes show a scam warning instead, because there the
customer is the victim. `risk-rules reason-codes` prints the catalogue.

## Features and models

`Features.of_context` is the only feature code: rules, models and the
training pipeline in `risk-models` all use it, so training rows exported
from journaled contexts are point-in-time by construction. The record has a
`schema_version`, a `schema` list (name and meaning, in export order), a
numeric vector (`to_floats`, booleans 0/1, missing values NaN) and a JSON
export (`to_json`/`of_json`, which checks the version). Changing a field's
meaning or adding one bumps the version and adds a `Stable` module.

A model implements `Model.S` (`name`, `version`, `score : Features.t ->
Score.t`). The policy names models; `Policy.evaluate ~models` supplies them
and `Policy.required_models` lists what a policy needs for a start-up check.
`Model.logistic` is a baseline and reference implementation.

## Policy files

See [`examples/policy.sexp`](examples/policy.sexp). Amounts are written as
`"<decimal> <currency>"` with the currency's full number of fractional
digits (`"0.00500000 BTC"`); spans as `10m`, `24h`, `7d`; fraud rates for
TRA in parts per million. Policies are validated on load: duplicate tiers,
duplicate currencies in one limit list, negative limits, non-positive
windows and counts, and unordered score thresholds are refused.

## CLI

```
risk-rules check-policy -policy examples/policy.sexp
risk-rules evaluate -policy examples/policy.sexp examples/context-card.sexp
risk-rules evaluate -policy examples/policy.sexp -constant-model fraud-gbt=0.9 examples/context-transfer.sexp
risk-rules features examples/context-transfer.sexp      # JSON feature record
risk-rules reason-codes                                 # code, typology, description, message
```

`evaluate` exits 0 on allow, 5 on challenge, 10 on review, 20 on block and
2 on a usage or parse error.

## Stable types and tests

`Severity`, `Reason_code`, `Typology`, `Hit`, `Decision`, `Tier`, `Country`,
`Mcc`, `Context`, `Features` and `Review_queue` have `Stable.V1` bin_io
types with their digests pinned in the expect tests. `Decision.t` is
private and re-derives its severity from its hits on read. `Context.Stable.V1`
embeds payments-core's stable transfer and beneficiary types, so its pinned
digest moves when those do; that test failing is the signal to re-check
journaled contexts. Tests: expect
tests per rule with evidence, policy loading and refusals, the example
files, the reason code catalogue, features and their JSON export, and
Quickcheck properties that adding a rule (generic or built-in) never lowers
a decision or drops a hit and that logistic scores stay in [0, 1].

Everything is verified on fixtures built from real payments-core values;
there is no external service and no credentials.

## Build

```
dune build @all @runtest
```

CI pins `fixed-decimal`, `money`, `ledger` and `payments-core` from GitHub
in that order.

## Known gaps

- Caps compare amounts in the transfer's own currency; there is no FX
  conversion, so limits split across EUR and USDC are checked per currency,
  and TRA applies only to EUR amounts.
- SCA exemptions covered: trusted beneficiaries and TRA. Own-account
  transfers, recurring payments and the low-value exemption need counters
  since the last authentication that `Context` does not carry yet; the
  observed fraud rate per TRA band comes from the policy, not from a rolling
  90-day fraud book.
- No sanctions name screening (that is a list-matching service); the
  country lists are the only sanctions control here.
- Card authorisations are not counted in transfer caps or velocity; card
  spend limits belong to the card library. Card testing works on the card
  history the caller supplies.
- `Context` fields come from the caller; the library does not check that
  the history belongs to the customer or that `now` is current.
