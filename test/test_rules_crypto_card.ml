open! Core
open Risk_rules
open Fixtures

let%expect_test "self-hosted wallet travel-rule hook" =
  let rule =
    Rules.unverified_self_hosted_wallet ~above:(limits [ btc "0.01000000" ]) ()
  in
  let to_wallet ~self_hosted ~ownership_verified amount =
    transfer
      ~rail:(Onchain Bitcoin)
      ~beneficiary:
        (beneficiary ~wallet:{ Context.Wallet.self_hosted; ownership_verified } ())
      amount
  in
  check
    rule
    (context (to_wallet ~self_hosted:true ~ownership_verified:false (btc "0.01000000")));
  check
    rule
    (context (to_wallet ~self_hosted:true ~ownership_verified:false (btc "0.01000001")));
  check
    rule
    (context (to_wallet ~self_hosted:true ~ownership_verified:true (btc "5.00000000")));
  check
    rule
    (context (to_wallet ~self_hosted:false ~ownership_verified:false (btc "5.00000000")));
  (* A bank transfer has no wallet. *)
  check rule (context (transfer (eur "100000.00")));
  [%expect
    {|
    -
    review: 0.01000001 BTC to an unverified self-hosted wallet above 0.01000000 BTC: collect travel-rule originator and beneficiary information or proof of ownership
    -
    -
    -
    |}]
;;

let%expect_test "merchant category block list" =
  let rule = Rules.blocked_mccs [ Mcc.of_int_exn 7995; Mcc.of_int_exn 6051 ] in
  check rule (context (card ~mcc:7995 (eur "20.00")));
  check rule (context (card ~mcc:5411 (eur "20.00")));
  check rule (context (transfer (eur "20.00")));
  [%expect {|
    block: merchant category 7995 is blocked
    -
    -
    |}]
;;

let%expect_test "online toggle" =
  let rule = Rules.online_toggle () in
  List.iter Context.Card_auth.Channel.all ~f:(fun channel ->
    List.iter [ true; false ] ~f:(fun online_enabled ->
      printf
        "%s online_enabled=%b: "
        (Sexp.to_string [%sexp (channel : Context.Card_auth.Channel.t)])
        online_enabled;
      check rule (context (card ~channel ~online_enabled (eur "20.00")))));
  [%expect
    {|
    In_person online_enabled=true: -
    In_person online_enabled=false: -
    Online online_enabled=true: -
    Online online_enabled=false: block: online payments are switched off for this card
    Atm online_enabled=true: -
    Atm online_enabled=false: -
    |}]
;;
