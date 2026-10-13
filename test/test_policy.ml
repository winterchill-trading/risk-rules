open! Core
open Risk_rules
open Fixtures

(* Tests run from the test directory of the build tree; the example is declared as a
   dependency in test/dune. *)
let example = Or_error.ok_exn (Policy.load "../examples/policy.sexp")

let%expect_test "example policy loads" =
  print_s [%sexp (Policy.tiers example : Tier.t list)];
  [%expect {| (basic verified under_review) |}];
  print_s
    [%sexp
      (List.length (Or_error.ok_exn (Policy.specs_for example (Tier.of_string "basic")))
       : int)];
  [%expect {| 22 |}]
;;

let show ctx = print_endline (Decision.to_string_hum (Policy.evaluate example ctx))

let%expect_test "tiers get different caps" =
  show (context ~tier:"basic" (transfer (eur "1500.00")));
  show (context ~tier:"verified" (transfer (eur "1500.00")));
  show (context ~tier:"under_review" (transfer (eur "1.00")));
  show (context ~tier:"vip" (transfer (eur "1.00")));
  [%expect
    {|
    block
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [allow] SCA_EXEMPT: exempt: trusted beneficiary (RTS article 13)
      per_transfer_cap [block] LIMIT_PER_TRANSFER: 1500.00 EUR exceeds the per-transfer cap of 1000.00 EUR
    allow
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [allow] SCA_EXEMPT: exempt: trusted beneficiary (RTS article 13)
    review
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [allow] SCA_EXEMPT: exempt: trusted beneficiary (RTS article 13)
      manual_review [review] MANUAL_REVIEW: customer under investigation
    block
      unknown_tier [block] UNKNOWN_TIER: no rules for tier vip
    |}]
;;

let%expect_test "all-tier rules apply to every tier" =
  let fresh = beneficiary ~first_seen:(ago (hours 1)) () in
  show
    (context
       ~tier:"verified"
       (transfer ~beneficiary:fresh ~country:(country "PA") (eur "5000.00")));
  show
    (context
       ~tier:"verified"
       (card ~mcc:7995 ~channel:Online ~online_enabled:false (eur "50.00")));
  [%expect
    {|
    block
      high_risk_country [review] GEO_HIGH_RISK: high-risk country: PA
      new_beneficiary_cooldown [block] NEW_BENEFICIARY_COOLDOWN: 5000.00 EUR to beneficiary ben-1 first seen 1h ago; above 250.00 EUR during the 1d cooldown
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [allow] SCA_EXEMPT: exempt: trusted beneficiary (RTS article 13)
    block
      blocked_mcc [block] CARD_MCC_BLOCKED: merchant category 7995 is blocked
      online_toggle [block] CARD_ONLINE_DISABLED: online payments are switched off for this card
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [allow] SCA_EXEMPT: exempt: transaction risk analysis (RTS article 18)
    |}]
;;

let%expect_test "severity override" =
  let policy =
    Or_error.ok_exn
      (Policy.of_string
         {|((tiers ((basic ((Severity Review (Per_transfer_cap ("100.00 EUR")))
                            (Severity Block (Severity Allow Online_toggle)))))))|})
  in
  print_endline
    (Decision.to_string_hum (Policy.evaluate policy (context (transfer (eur "200.00")))));
  print_endline
    (Decision.to_string_hum
       (Policy.evaluate
          policy
          (context (card ~channel:Online ~online_enabled:false (eur "1.00")))));
  [%expect
    {|
    review
      per_transfer_cap [review] LIMIT_PER_TRANSFER: 200.00 EUR exceeds the per-transfer cap of 100.00 EUR
    block
      online_toggle [block] CARD_ONLINE_DISABLED: online payments are switched off for this card
    |}]
;;

let%expect_test "invalid policies are refused" =
  let try_ text =
    print_s [%sexp (Or_error.map (Policy.of_string text) ~f:ignore : unit Or_error.t)]
  in
  try_ "((tiers ((basic ()) (basic ()))))";
  try_ "((tiers ((basic ((Velocity (max_count 0) (window 10m)))))))";
  try_ {|((tiers ((basic ((Per_transfer_cap ("1.00 EUR" "2.00 EUR")))))))|};
  try_ {|((tiers ((basic ((Per_transfer_cap ("-1.00 EUR")))))))|};
  try_ "((tiers ((Basic ()))))";
  try_
    "((tiers ((basic ((Structuring (threshold ()) (round_unit ()) (margin_bps 20000) \
     (min_count 0) (window 0s)))))))";
  [%expect
    {|
    (Error ("policy: tier listed twice" (tier basic)))
    (Error ("rule spec: must be positive" max_count (n 0)))
    (Error ("limits: currency listed twice" (currency EUR)))
    (Error ("limits: negative limit" (amount "-1.00 EUR")))
    (Error ("tier: invalid name" (s Basic)))
    (Error
     (("rule spec: margin_bps outside 0..10000" (margin_bps 20000))
      ("rule spec: must be positive" min_count (n 0))
      ("rule spec: window must be positive" window (span 0s))))
    |}]
;;

let%expect_test "policy sexp round trip" =
  let again =
    Or_error.ok_exn (Policy.of_string (Sexp.to_string (Policy.sexp_of_t example)))
  in
  print_s [%sexp (Policy.equal example again : bool)];
  [%expect {| true |}]
;;
