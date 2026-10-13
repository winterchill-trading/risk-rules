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
      new_beneficiary_cooldown [block] 750.00 EUR to beneficiary ben-1 first seen 2h ago; above 250.00 EUR during the 1d cooldown
    block
      blocked_mcc [block] merchant category 7995 is blocked
      online_toggle [block] online payments are switched off for this card
    |}]
;;
