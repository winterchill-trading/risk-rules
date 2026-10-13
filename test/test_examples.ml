open! Core
open Risk_rules

(* The files under examples/ are what the README and the CLI help point to; keep them
   parsing and keep their outcomes visible here. *)
let policy = Or_error.ok_exn (Policy.load "../examples/policy.sexp")

let evaluate file =
  let ctx = Sexp.load_sexp_conv_exn ("../examples/" ^ file) Context.t_of_sexp in
  print_endline (Decision.to_string_hum (Policy.evaluate policy ctx))
;;

let%expect_test "example contexts" =
  evaluate "context-transfer.sexp";
  evaluate "context-card.sexp";
  [%expect
    {|
    block
      new_beneficiary_cooldown [block] NEW_BENEFICIARY_COOLDOWN: 750.00 EUR to beneficiary ben-1 first seen 2h ago; above 250.00 EUR during the 1d cooldown
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [challenge] SCA_REQUIRED: no SCA exemption: 750.00 EUR is above the 500.00 EUR exemption threshold; risk signals: new_beneficiary
    block
      blocked_mcc [block] CARD_MCC_BLOCKED: merchant category 7995 is blocked
      online_toggle [block] CARD_ONLINE_DISABLED: online payments are switched off for this card
      model_score [allow] SCORE_UNAVAILABLE: model fraud-gbt is not loaded
      sca_tra [allow] SCA_EXEMPT: exempt: transaction risk analysis (RTS article 18)
    |}]
;;
