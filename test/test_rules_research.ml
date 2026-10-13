open! Core
open Risk_rules
open Fixtures

let explain rule ctx =
  match Rule.check rule ctx with
  | None -> print_endline "-"
  | Some hit ->
    printf
      "%s %s: %s\n"
      (Severity.to_string hit.severity)
      (Reason_code.to_string hit.code)
      hit.reason
;;

let opened_days_ago d =
  { Context.Session.unknown with account_opened_at = Some (ago (hours (24 * d))) }
;;

let from sender h amount = { (past (hours h) amount) with sender = Some sender }

let%expect_test "mule fan-in" =
  let rule =
    Rules.mule_fan_in
      ~min_senders:3
      ~window:(hours 24)
      ~max_account_age:(hours (24 * 30))
      ()
  in
  let incoming =
    [ from "a" 1 (eur "100.00")
    ; from "b" 2 (eur "100.00")
    ; from "c" 3 (eur "100.00")
    ; from "a" 4 (eur "5.00")
    ]
  in
  explain rule (context ~incoming ~session:(opened_days_ago 10) (transfer (eur "250.00")));
  (* Old account, or unknown opening date. *)
  explain rule (context ~incoming ~session:(opened_days_ago 90) (transfer (eur "250.00")));
  explain rule (context ~incoming (transfer (eur "250.00")));
  explain
    rule
    (context
       ~incoming:(List.take incoming 2)
       ~session:(opened_days_ago 10)
       (transfer (eur "250.00")));
  [%expect
    {|
    review MULE_FAN_IN: 3 distinct payers in 1d into an account opened 10d ago
    -
    -
    -
    |}]
;;

let%expect_test "new account payout" =
  let rule =
    Rules.new_account_payout ~max_age:(hours (24 * 7)) ~above:(limits [ eur "500.00" ]) ()
  in
  explain rule (context ~session:(opened_days_ago 2) (transfer (eur "600.00")));
  explain rule (context ~session:(opened_days_ago 2) (transfer (eur "400.00")));
  explain rule (context ~session:(opened_days_ago 8) (transfer (eur "600.00")));
  [%expect
    {|
    review NEW_ACCOUNT_PAYOUT: 600.00 EUR from an account opened 2d ago (above 500.00 EUR)
    -
    -
    |}]
;;

let%expect_test "first large payment to a new payee" =
  let rule = Rules.app_first_large_payment ~new_within:(hours 48) () in
  let history = [ past (hours 30) (eur "100.00"); past (hours 300) (eur "60.00") ] in
  let fresh = beneficiary ~first_seen:(ago (hours 1)) () in
  explain rule (context ~history (transfer ~beneficiary:fresh (eur "401.00")));
  explain rule (context ~history (transfer ~beneficiary:fresh (eur "400.00")));
  explain rule (context ~history (transfer (eur "5000.00")));
  explain rule (context (transfer ~beneficiary:fresh (eur "5000.00")));
  [%expect
    {|
    review APP_FIRST_LARGE_PAYMENT: 401.00 EUR to beneficiary ben-1 first seen 1h ago is over 5x the 30-day mean of 2 transfers totalling 160.00 EUR
    -
    -
    -
    |}]
;;

let%expect_test "verification of payee" =
  let rule = Rules.vop_not_matched () in
  let with_check check = { (beneficiary ()) with payee_check = Some check } in
  List.iter
    Payments_core.Beneficiary.Payee_check.
      [ Match; Close_match { suggested_name = "A. Example" }; No_match; Not_possible ]
    ~f:(fun check ->
      explain rule (context (transfer ~beneficiary:(with_check check) (eur "10.00"))));
  [%expect
    {|
    -
    review VOP_NOT_MATCHED: verification of payee: close match, holder is A. Example
    review VOP_NOT_MATCHED: verification of payee: no match
    -
    |}]
;;

let%expect_test "card testing" =
  let rule =
    Rules.card_testing ~small:(limits [ eur "2.00" ]) ~count:5 ~window:(minutes 10) ()
  in
  let auth m amount approved =
    { Context.Past_auth.at = ago (minutes m); amount; merchant = "m"; approved }
  in
  let small n = List.init n ~f:(fun i -> auth (i + 1) (eur "0.50") true) in
  explain rule (context ~card_history:(small 5) (card ~channel:Online (eur "300.00")));
  explain rule (context ~card_history:(small 4) (card ~channel:Online (eur "300.00")));
  explain
    rule
    (context
       ~card_history:
         [ auth 1 (eur "50.00") false
         ; auth 2 (eur "50.00") false
         ; auth 3 (eur "50.00") false
         ]
       (card (eur "50.00")));
  (* Outside the window. *)
  explain
    rule
    (context
       ~card_history:(List.map (small 5) ~f:(fun a -> { a with at = ago (minutes 30) }))
       (card (eur "1.00")));
  [%expect
    {|
    block CARD_TESTING: 5 authorisations below 2.00 EUR and 0 declines in 10m
    -
    block CARD_TESTING: 0 authorisations below 2.00 EUR and 3 declines in 10m
    -
    |}]
;;

let%expect_test "takeover with a large share of the balance" =
  let rule =
    Rules.account_takeover ~min_signals:4 ~balance_share_bps:9_000 ~recent:(hours 24) ()
  in
  let session =
    { Context.Session.unknown with
      new_device = true
    ; credentials_changed_at = Some (ago (hours 3))
    }
  in
  let fresh = beneficiary ~first_seen:(ago (hours 1)) () in
  explain
    rule
    (context
       ~balances:[ eur "1000.00" ]
       ~session
       (transfer ~beneficiary:fresh (eur "950.00")));
  explain
    rule
    (context
       ~balances:[ eur "1000.00" ]
       ~session
       (transfer ~beneficiary:fresh (eur "100.00")));
  [%expect
    {|
    review ACCOUNT_TAKEOVER_SIGNALS: 4 account takeover signals: new_device, credentials_changed, new_beneficiary, large_share_of_balance
    -
    |}]
;;

let%expect_test "shadow mode logs without deciding" =
  let policy =
    Policy.of_string
      {|((tiers ((basic ((Shadow (Per_transfer_cap ("10.00 EUR")))
                        (Shadow (Score (model m) (thresholds ((block_at 0.1))))))))))|}
    |> Or_error.ok_exn
  in
  let d =
    Policy.evaluate
      ~models:[ Model.constant ~name:"m" 0.9 ]
      policy
      (context (transfer (eur "20.00")))
  in
  print_endline (Decision.to_string_hum d);
  [%expect
    {|
    allow
      per_transfer_cap [allow] LIMIT_PER_TRANSFER: 20.00 EUR exceeds the per-transfer cap of 10.00 EUR
      model_score [allow] SCORE_HIGH: m constant scored 0.9000
    |}]
;;

let%expect_test "decision messages and codes" =
  let policy = Or_error.ok_exn (Policy.load "../examples/policy.sexp") in
  let show ctx =
    let d = Policy.evaluate policy ctx in
    print_s
      [%sexp
        (d.severity : Severity.t)
        , (Decision.reason_codes d : Reason_code.t list)
        , (Decision.customer_message d : string option)]
  in
  show (context ~tier:"verified" (transfer (eur "10.00")));
  show (context ~tier:"basic" (transfer (eur "1500.00")));
  show
    (context
       ~tier:"verified"
       ~balances:[ eur "3000.00" ]
       (transfer
          ~beneficiary:(beneficiary ~first_seen:(ago (hours 1)) ~trusted:false ())
          (eur "2900.00")));
  [%expect
    {|
    (Allow () ())
    (Block (LIMIT_PER_TRANSFER)
     ("This payment is above your limit for a single payment."))
    (Block (NEW_BENEFICIARY_COOLDOWN)
     ("Payments to a newly added payee are limited for a short time. Please try a smaller amount or try again later."))
    |}]
;;

let%expect_test "policy refers to models by name" =
  let policy =
    Policy.of_string
      {|((all_tiers ((Score (model fraud) (thresholds ((review_at 0.8))))))
         (tiers ((basic ()))))|}
    |> Or_error.ok_exn
  in
  print_s [%sexp (Policy.required_models policy : string list)];
  let ctx = context (transfer (eur "10.00")) in
  print_endline (Decision.to_string_hum (Policy.evaluate policy ctx));
  print_endline
    (Decision.to_string_hum
       (Policy.evaluate ~models:[ Model.constant ~name:"fraud" 0.85 ] policy ctx));
  [%expect
    {|
    (fraud)
    review
      model_score [review] SCORE_UNAVAILABLE: model fraud is not loaded
    review
      model_score [review] SCORE_HIGH: fraud constant scored 0.8500
    |}]
;;
