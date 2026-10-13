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
    ~incoming:
      [ { (past (hours 3) (eur "900.00")) with sender = Some "payer-a" }
      ; { (past (hours 4) (eur "50.00")) with sender = Some "payer-b" }
      ]
    ~geo:{ ip_country = Some (country "NG"); residence = Some (country "DE") }
    ~session:
      { new_device = true
      ; credentials_changed_at = Some (ago (hours 6))
      ; account_opened_at = Some (ago (hours (24 * 45)))
      ; failed_sca_24h = 1
      }
    (transfer
       ~beneficiary:(beneficiary ~first_seen:(ago (hours 2)) ~trusted:false ())
       (eur "700.00"))
;;

(* [log1p] comes from the platform maths library and may differ in the last bits between
   macOS and glibc; round it before printing. *)
let stable (f : Features.t) =
  { f with log1p_amount = Float.round_decimal f.log1p_amount ~decimal_digits:9 }
;;

let%expect_test "features of a transfer" =
  print_s [%sexp (stable (Features.of_context (rich_context ())) : Features.t)];
  [%expect
    {|
    ((schema_version 1) (is_card false) (rail sepa_instant) (card_channel ())
     (currency EUR) (amount 700) (amount_is_round true) (balance (1000))
     (amount_to_balance (0.7)) (beneficiary_age_hours (2))
     (beneficiary_trusted (false)) (counterparty_country_is_residence (true))
     (self_hosted_unverified false) (mcc ()) (out_count_1h 1) (out_count_24h 3)
     (out_sum_24h 150) (out_sum_30d 550) (out_distinct_beneficiaries_24h 1)
     (in_count_24h 2) (in_sum_24h 950)
     (pass_through_ratio_24h (0.89473684210526316)) (new_device true)
     (ip_country_is_residence (false)) (hours_since_credentials_change (6))
     (account_age_days (45)) (hour_of_day_utc 12) (log1p_amount 6.552507887)
     (is_weekend false) (out_count_7d 3) (out_sum_1h 100) (out_sum_7d 150)
     (amount_over_mean_30d (3.8181818181818179)) (in_distinct_senders_24h 2)
     (minutes_since_last_inbound (180)) (failed_sca_24h 1) (payee_check ())
     (card_auths_10m 0) (card_declines_10m 0))
    |}]
;;

let%expect_test "features of a card authorisation" =
  print_s
    [%sexp
      (stable
       @@ Features.of_context
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
     (hour_of_day_utc 12) (log1p_amount 3.713572067) (is_weekend false)
     (out_count_7d 0) (out_sum_1h 0) (out_sum_7d 0) (amount_over_mean_30d ())
     (in_distinct_senders_24h 0) (minutes_since_last_inbound ())
     (failed_sca_24h 0) (payee_check ()) (card_auths_10m 0)
     (card_declines_10m 0))
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
  [%expect {| (39 34) |}]
;;

let%expect_test "json export round trips and checks the version" =
  let t = stable (Features.of_context (rich_context ())) in
  let json = Features.to_json t in
  print_endline json;
  [%expect
    {| {"schema_version":1,"is_card":false,"rail":"sepa_instant","card_channel":null,"currency":"EUR","amount":700.0,"amount_is_round":true,"balance":1000.0,"amount_to_balance":0.7,"beneficiary_age_hours":2.0,"beneficiary_trusted":false,"counterparty_country_is_residence":true,"self_hosted_unverified":false,"mcc":null,"out_count_1h":1,"out_count_24h":3,"out_sum_24h":150.0,"out_sum_30d":550.0,"out_distinct_beneficiaries_24h":1,"in_count_24h":2,"in_sum_24h":950.0,"pass_through_ratio_24h":0.8947368421052632,"new_device":true,"ip_country_is_residence":false,"hours_since_credentials_change":6.0,"account_age_days":45.0,"hour_of_day_utc":12,"log1p_amount":6.552507887,"is_weekend":false,"out_count_7d":3,"out_sum_1h":100.0,"out_sum_7d":150.0,"amount_over_mean_30d":3.818181818181818,"in_distinct_senders_24h":2,"minutes_since_last_inbound":180.0,"failed_sca_24h":1,"payee_check":null,"card_auths_10m":0,"card_declines_10m":0} |}];
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
  [%expect {| 023713ce02561ba00831e1d0ffc5e9fd |}]
;;
