open! Core
open Risk_rules
open Fixtures

let rich_context () =
  context
    ~balances:[ eur "1000.00" ]
    ~history:
      [ past (minutes 30) (eur "100.00")
      ; past (hours 5) (eur "50.00")
      ; past (hours (24 * 10)) (eur "400.00")
      ; past (hours 2) (btc "0.10000000")
      ]
    ~incoming:[ past (hours 3) (eur "900.00") ]
    ~geo:{ ip_country = Some (country "NG"); residence = Some (country "DE") }
    ~session:
      { new_device = true
      ; credentials_changed_at = Some (ago (hours 6))
      ; account_opened_at = Some (ago (hours (24 * 45)))
      }
    (transfer
       ~beneficiary:(beneficiary ~first_seen:(ago (hours 2)) ~trusted:false ())
       (eur "700.00"))
;;

let%expect_test "features of a transfer" =
  print_s [%sexp (Features.of_context (rich_context ()) : Features.t)];
  [%expect
    {|
    ((schema_version 1) (is_card false) (rail sepa_instant) (card_channel ())
     (currency EUR) (amount 700) (amount_is_round true) (balance (1000))
     (amount_to_balance (0.7)) (beneficiary_age_hours (2))
     (beneficiary_trusted (false)) (counterparty_country_is_residence (true))
     (self_hosted_unverified false) (mcc ()) (out_count_1h 1) (out_count_24h 3)
     (out_sum_24h 150) (out_sum_30d 550) (out_distinct_beneficiaries_24h 1)
     (in_count_24h 1) (in_sum_24h 900)
     (pass_through_ratio_24h (0.94444444444444442)) (new_device true)
     (ip_country_is_residence (false)) (hours_since_credentials_change (6))
     (account_age_days (45)) (hour_of_day_utc 12))
    |}]
;;

let%expect_test "features of a card authorisation" =
  print_s
    [%sexp
      (Features.of_context
         (context
            (card
               ~mcc:7995
               ~channel:Online
               ~merchant_country:(country "MT")
               (eur "40.00")))
       : Features.t)];
  [%expect
    {|
    ((schema_version 1) (is_card true) (rail card) (card_channel (Online))
     (currency EUR) (amount 40) (amount_is_round false) (balance (10000))
     (amount_to_balance (0.004)) (beneficiary_age_hours ())
     (beneficiary_trusted ()) (counterparty_country_is_residence ())
     (self_hosted_unverified false) (mcc (7995)) (out_count_1h 0)
     (out_count_24h 0) (out_sum_24h 0) (out_sum_30d 0)
     (out_distinct_beneficiaries_24h 0) (in_count_24h 0) (in_sum_24h 0)
     (pass_through_ratio_24h ()) (new_device false) (ip_country_is_residence ())
     (hours_since_credentials_change ()) (account_age_days ())
     (hour_of_day_utc 12))
    |}]
;;

let%expect_test "schema covers every field, in record order" =
  let t = Features.of_context (rich_context ()) in
  let fields =
    match Features.sexp_of_t t with
    | List fields ->
      List.map fields ~f:(function
        | List (Atom name :: _) -> name
        | sexp -> raise_s [%message "unexpected" (sexp : Sexp.t)])
    | Atom _ -> assert false
  in
  (* Option fields that are [None] still appear in the sexp: no [@sexp.option]. *)
  [%test_result: string list] ~expect:fields (List.map Features.schema ~f:fst);
  [%test_result: string list]
    ~expect:Features.numeric_names
    (List.map (Features.to_floats t) ~f:fst);
  print_s
    [%sexp
      (List.length Features.schema : int), (List.length Features.numeric_names : int)];
  [%expect {| (27 23) |}]
;;

let%expect_test "json export round trips and checks the version" =
  let t = Features.of_context (rich_context ()) in
  let json = Features.to_json t in
  print_endline json;
  [%expect
    {| {"schema_version":1,"is_card":false,"rail":"sepa_instant","card_channel":null,"currency":"EUR","amount":700.0,"amount_is_round":true,"balance":1000.0,"amount_to_balance":0.7,"beneficiary_age_hours":2.0,"beneficiary_trusted":false,"counterparty_country_is_residence":true,"self_hosted_unverified":false,"mcc":null,"out_count_1h":1,"out_count_24h":3,"out_sum_24h":150.0,"out_sum_30d":550.0,"out_distinct_beneficiaries_24h":1,"in_count_24h":1,"in_sum_24h":900.0,"pass_through_ratio_24h":0.9444444444444444,"new_device":true,"ip_country_is_residence":false,"hours_since_credentials_change":6.0,"account_age_days":45.0,"hour_of_day_utc":12} |}];
  assert (Features.equal t (Or_error.ok_exn (Features.of_json json)));
  let other =
    String.substr_replace_first
      json
      ~pattern:{|"schema_version":1|}
      ~with_:{|"schema_version":2|}
  in
  print_s [%sexp (Features.of_json other |> Or_error.map ~f:ignore : unit Or_error.t)];
  [%expect {| (Error ("features: schema version mismatch" (expected 1) (got 2))) |}]
;;

let%expect_test "stable digest" =
  print_endline [%bin_digest: Features.Stable.V1.t];
  [%expect {| 9b44dbb0299a258a9e9dbbf8784cbbac |}]
;;
