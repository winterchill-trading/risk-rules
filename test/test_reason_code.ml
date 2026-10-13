open! Core
open Risk_rules

let%expect_test "every built-in code round trips and has texts" =
  List.iter Reason_code.builtin ~f:(fun code ->
    let s = Reason_code.to_string code in
    [%test_result: Reason_code.t] ~expect:code (Reason_code.of_string s);
    [%test_result: Reason_code.t]
      ~expect:code
      (Reason_code.t_of_sexp (Reason_code.sexp_of_t code));
    assert (not (String.is_empty (Reason_code.description code)));
    assert (not (String.is_empty (Reason_code.customer_message code)));
    printf "%s %s\n" s (Typology.to_string (Reason_code.typology code)));
  [%expect
    {|
    LIMIT_PER_TRANSFER limits
    LIMIT_DAILY limits
    LIMIT_MONTHLY limits
    LIMIT_WINDOW limits
    VELOCITY_OUT velocity
    NEW_BENEFICIARY_COOLDOWN account_takeover
    STRUCTURING structuring
    GEO_BLOCKED sanctions_geography
    GEO_HIGH_RISK sanctions_geography
    TRAVEL_RULE_SELF_HOSTED travel_rule
    CARD_MCC_BLOCKED card_controls
    CARD_ONLINE_DISABLED card_controls
    MANUAL_REVIEW operational
    MULE_PASS_THROUGH money_mule
    ACCOUNT_TAKEOVER_SIGNALS account_takeover
    APP_NEW_BENEFICIARY_BALANCE app_fraud
    MULE_FAN_IN money_mule
    NEW_ACCOUNT_PAYOUT money_mule
    VOP_NOT_MATCHED app_fraud
    CARD_TESTING card_controls
    APP_FIRST_LARGE_PAYMENT app_fraud
    SCA_EXEMPT strong_authentication
    SCORE_HIGH model_score
    SCORE_UNAVAILABLE model_score
    SCA_REQUIRED strong_authentication
    RULE_ERROR operational
    UNKNOWN_TIER operational
    |}]
;;

let%expect_test "custom codes" =
  let c = Reason_code.Custom "VIP_OVERRIDE" in
  print_s
    [%sexp
      (c : Reason_code.t), (Reason_code.of_string "CUSTOM_VIP_OVERRIDE" : Reason_code.t)];
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Reason_code.of_string "NOT_A_CODE")
       |> Or_error.is_error
       : bool)];
  [%expect {|
    (CUSTOM_VIP_OVERRIDE CUSTOM_VIP_OVERRIDE)
    true
    |}];
  print_endline [%bin_digest: Reason_code.Stable.V1.t];
  print_endline [%bin_digest: Typology.Stable.V1.t];
  [%expect
    {|
    cc68beb0498cd26af9cf24eb5a155f88
    6594ee392e0e137c5093e17087428eee
    |}]
;;

(* Suspicion typologies must not tell the customer what was suspected. *)
let%expect_test "suspicion codes share the neutral message" =
  List.iter
    Reason_code.
      [ Structuring
      ; Mule_pass_through
      ; Mule_fan_in
      ; Account_takeover_signals
      ; Score_high
      ]
    ~f:(fun code -> print_endline (Reason_code.customer_message code));
  [%expect
    {|
    We need to check this payment before it can be sent.
    We need to check this payment before it can be sent.
    We need to check this payment before it can be sent.
    We need to check this payment before it can be sent.
    We need to check this payment before it can be sent.
    |}]
;;
