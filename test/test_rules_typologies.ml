open! Core
open Risk_rules
open Fixtures

(* Prints the rule's verdict with its code and evidence. *)
let explain rule ctx =
  match Rule.check rule ctx with
  | None -> print_endline "-"
  | Some hit ->
    printf
      "%s %s: %s\n"
      (Severity.to_string hit.severity)
      (Reason_code.to_string hit.code)
      hit.reason;
    List.iter hit.evidence ~f:(fun (k, v) -> printf "  %s=%s\n" k v)
;;

let%expect_test "money mule pass-through" =
  let rule =
    Rules.mule_pass_through ~window:(hours 24) ~min_incoming:(limits [ eur "500.00" ]) ()
  in
  let incoming = [ past (hours 3) (eur "1000.00") ] in
  explain
    rule
    (context
       ~incoming
       ~history:[ past (hours 1) (eur "300.00") ]
       (transfer (eur "500.00")));
  (* 300 + 400 = 70% of what came in: below the 80% default. *)
  explain
    rule
    (context
       ~incoming
       ~history:[ past (hours 1) (eur "300.00") ]
       (transfer (eur "400.00")));
  (* Too little came in to matter. *)
  explain
    rule
    (context ~incoming:[ past (hours 3) (eur "100.00") ] (transfer (eur "100.00")));
  [%expect
    {|
    review MULE_PASS_THROUGH: 1000.00 EUR received and 800.00 EUR sent on (this one included) within 1d
      incoming=1000.00 EUR
      outgoing=800.00 EUR
      ratio_bps=8000
      window=1d
    -
    -
    |}]
;;

let%expect_test "account takeover signals" =
  let rule = Rules.account_takeover ~recent:(hours 24) () in
  let session = { Context.Session.unknown with new_device = true } in
  let geo =
    { Context.Geo.ip_country = Some (country "NG"); residence = Some (country "DE") }
  in
  (* One signal is not enough. *)
  explain rule (context ~session (transfer (eur "10.00")));
  explain rule (context ~session ~geo (transfer (eur "10.00")));
  explain
    rule
    (context
       ~session:{ session with credentials_changed_at = Some (ago (hours 2)) }
       (transfer ~beneficiary:(beneficiary ~first_seen:(ago (hours 1)) ()) (eur "10.00")));
  (* In-person card payments are not remote. *)
  explain rule (context ~session ~geo (card (eur "10.00")));
  explain rule (context ~session ~geo (card ~channel:Online (eur "10.00")));
  [%expect
    {|
    -
    review ACCOUNT_TAKEOVER_SIGNALS: 2 account takeover signals: new_device, ip_outside_residence
      signal=new_device
      signal=ip_outside_residence
      min_signals=2
      recent=1d
    review ACCOUNT_TAKEOVER_SIGNALS: 3 account takeover signals: new_device, credentials_changed, new_beneficiary
      signal=new_device
      signal=credentials_changed
      signal=new_beneficiary
      min_signals=2
      recent=1d
    -
    review ACCOUNT_TAKEOVER_SIGNALS: 2 account takeover signals: new_device, ip_outside_residence
      signal=new_device
      signal=ip_outside_residence
      min_signals=2
      recent=1d
    |}]
;;

let%expect_test "push payment fraud: new beneficiary, most of the balance" =
  let rule = Rules.app_fraud ~new_within:(hours 48) () in
  let fresh = beneficiary ~first_seen:(ago (hours 3)) () in
  explain
    rule
    (context ~balances:[ eur "5000.00" ] (transfer ~beneficiary:fresh (eur "4500.00")));
  explain
    rule
    (context ~balances:[ eur "5000.00" ] (transfer ~beneficiary:fresh (eur "1000.00")));
  explain rule (context ~balances:[ eur "5000.00" ] (transfer (eur "4500.00")));
  (* No balance known in the currency: nothing to compare. *)
  explain rule (context ~balances:[] (transfer ~beneficiary:fresh (eur "4500.00")));
  [%expect
    {|
    review APP_NEW_BENEFICIARY_BALANCE: 4500.00 EUR of an available 5000.00 EUR to beneficiary ben-1 first seen 3h ago
      amount=4500.00 EUR
      balance=5000.00 EUR
      beneficiary_age=3h
      balance_share_bps=8000
    -
    -
    -
    |}]
;;

let constant value = Model.constant ~name:"const" value

let%expect_test "model score thresholds" =
  let thresholds =
    { Rules.Thresholds.challenge_at = Some 0.5
    ; review_at = Some 0.8
    ; block_at = Some 0.95
    }
  in
  List.iter [ 0.1; 0.5; 0.85; 0.99 ] ~f:(fun v ->
    explain (Rules.model_score (constant v) thresholds) (context (transfer (eur "10.00"))));
  [%expect
    {|
    -
    challenge SCORE_HIGH: const constant scored 0.5000
      model=const
      model_version=constant
      score=0.5000
    review SCORE_HIGH: const constant scored 0.8500
      model=const
      model_version=constant
      score=0.8500
    block SCORE_HIGH: const constant scored 0.9900
      model=const
      model_version=constant
      score=0.9900
    |}];
  print_s
    [%sexp
      (Rules.Thresholds.validate
         { challenge_at = Some 0.9; review_at = Some 0.5; block_at = None }
       : unit Or_error.t)];
  [%expect {| (Error "score thresholds must satisfy challenge <= review <= block") |}]
;;

let%expect_test "TRA exemption bands" =
  List.iter Rules.Tra.all_of_scheme ~f:(fun scheme ->
    List.iter [ 10; 50; 100; 150; 600; 1300; 2000 ] ~f:(fun ppm ->
      printf
        "%s %d ppm -> %s\n"
        (Sexp.to_string [%sexp (scheme : Rules.Tra.scheme)])
        ppm
        (Option.value_map
           (Rules.Tra.threshold scheme ~observed_fraud_rate_ppm:ppm)
           ~default:"none"
           ~f:Money.Amount.to_string)));
  [%expect
    {|
    Credit_transfer 10 ppm -> 500.00 EUR
    Credit_transfer 50 ppm -> 500.00 EUR
    Credit_transfer 100 ppm -> 250.00 EUR
    Credit_transfer 150 ppm -> 100.00 EUR
    Credit_transfer 600 ppm -> none
    Credit_transfer 1300 ppm -> none
    Credit_transfer 2000 ppm -> none
    Card_not_present 10 ppm -> 500.00 EUR
    Card_not_present 50 ppm -> 500.00 EUR
    Card_not_present 100 ppm -> 500.00 EUR
    Card_not_present 150 ppm -> 250.00 EUR
    Card_not_present 600 ppm -> 250.00 EUR
    Card_not_present 1300 ppm -> 100.00 EUR
    Card_not_present 2000 ppm -> none
    |}]
;;

let%expect_test "SCA unless an exemption applies" =
  let rule = Rules.sca_tra ~scheme:Credit_transfer ~observed_fraud_rate_ppm:90 () in
  let untrusted = beneficiary ~trusted:false () in
  (* 90 ppm allows up to 250 EUR. *)
  explain rule (context (transfer ~beneficiary:untrusted (eur "200.00")));
  explain rule (context (transfer ~beneficiary:untrusted (eur "300.00")));
  (* Trusted beneficiaries are exempt (article 13). *)
  explain rule (context (transfer (eur "300.00")));
  (* A takeover signal cancels the TRA exemption. *)
  explain
    rule
    (context
       ~session:{ Context.Session.unknown with new_device = true }
       (transfer ~beneficiary:untrusted (eur "50.00")));
  (* Non-EUR amounts have no threshold to compare to. *)
  explain
    rule
    (context
       (transfer ~beneficiary:(wallet_beneficiary ~trusted:false ()) (btc "0.00100000")));
  [%expect
    {|
    -
    challenge SCA_REQUIRED: no SCA exemption: 300.00 EUR is above the 250.00 EUR exemption threshold
      scheme=Credit_transfer
      observed_fraud_rate_ppm=90
      tra_threshold=250.00 EUR
    -
    challenge SCA_REQUIRED: no SCA exemption: risk signals: new_device
      scheme=Credit_transfer
      observed_fraud_rate_ppm=90
      tra_threshold=250.00 EUR
      signal=new_device
    challenge SCA_REQUIRED: no SCA exemption: not in EUR (no conversion to the EUR thresholds)
      scheme=Credit_transfer
      observed_fraud_rate_ppm=90
      tra_threshold=250.00 EUR
    |}];
  let with_model =
    Rules.sca_tra
      ~scheme:Credit_transfer
      ~observed_fraud_rate_ppm:90
      ~model:(constant 0.7, 0.6)
      ()
  in
  explain with_model (context (transfer ~beneficiary:untrusted (eur "20.00")));
  let cnp = Rules.sca_tra ~scheme:Card_not_present ~observed_fraud_rate_ppm:700 () in
  explain cnp (context (card ~channel:Online (eur "90.00")));
  explain cnp (context (card ~channel:Online (eur "120.00")));
  explain cnp (context (card ~channel:In_person (eur "120.00")));
  [%expect
    {|
    challenge SCA_REQUIRED: no SCA exemption: score 0.7000 at or above 0.6000
      scheme=Credit_transfer
      observed_fraud_rate_ppm=90
      tra_threshold=250.00 EUR
      model=const
      model_version=constant
      score=0.7000
    -
    challenge SCA_REQUIRED: no SCA exemption: 120.00 EUR is above the 100.00 EUR exemption threshold
      scheme=Card_not_present
      observed_fraud_rate_ppm=700
      tra_threshold=100.00 EUR
    -
    |}]
;;
