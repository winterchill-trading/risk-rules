open! Core
open Risk_rules
open Fixtures

(* A pool of built-in specs; the property picks random subsets so it runs against real
   rules, not only the int stand-ins in test_engine.ml. *)
let pool =
  let l = limits in
  [ Rule_spec.Per_transfer_cap (l [ eur "500.00" ])
  ; Daily_cap (l [ eur "800.00" ])
  ; Monthly_cap (l [ eur "3000.00" ])
  ; Velocity { max_count = 3; window = hours 1 }
  ; New_beneficiary_cooldown
      { cooldown = hours 24; above = l [ eur "100.00" ]; exempt_trusted = false }
  ; Structuring
      { threshold = l [ eur "1000.00" ]
      ; round_unit = l [ eur "100.00" ]
      ; margin_bps = 1_000
      ; min_count = 2
      ; window = hours 72
      }
  ; Blocked_countries [ country "DE" ]
  ; High_risk_countries [ country "FR" ]
  ; Blocked_mccs [ Mcc.of_int_exn 7995 ]
  ; Online_toggle
  ; Severity (Review, Per_transfer_cap (l [ eur "50.00" ]))
  ; Severity (Allow, Velocity { max_count = 1; window = hours 24 })
  ; Mule_pass_through
      { window = hours 24; min_incoming = l [ eur "10.00" ]; ratio_bps = 8_000 }
  ; Account_takeover
      { recent = hours 24; min_signals = 1; balance_share_bps = Some 5_000 }
  ; App_fraud { new_within = hours 48; balance_share_bps = 5_000 }
  ; App_first_large_payment { new_within = hours 48; multiple = 2 }
  ; Sca_tra
      { scheme = Credit_transfer
      ; observed_fraud_rate_ppm = 40
      ; trusted_beneficiaries_exempt = true
      ; recent = hours 24
      ; model = Some "m"
      ; max_score = 0.5
      }
  ; Score
      { model = "m"
      ; thresholds =
          { challenge_at = Some 0.3; review_at = Some 0.6; block_at = Some 0.9 }
      }
  ; Shadow (Per_transfer_cap (l [ eur "1.00" ]))
  ; Score
      { model = "missing"
      ; thresholds = { challenge_at = None; review_at = Some 0.5; block_at = None }
      }
  ]
;;

(* A model whose score depends on the features, so the properties see every threshold
   band. *)
let model =
  Model.logistic
    ~name:"m"
    ~version:"test"
    ~intercept:(-2.)
    ~weights:[ "amount_to_balance", 4.; "out_count_24h", 0.5 ]
    ()
  |> Or_error.ok_exn
;;

let to_rule = Rule_spec.to_rule ~models:[ model ]
let gen_spec = Quickcheck.Generator.of_list pool

let gen_amount =
  Quickcheck.Generator.map (Int.gen_incl 1 200_000) ~f:(fun cents ->
    Money.Amount.of_minor_units_int Money.Currency.eur cents)
;;

let gen_context =
  let open Quickcheck.Let_syntax in
  let%bind amount = gen_amount
  and history =
    List.gen_with_length
      4
      (let%map minutes_ago = Int.gen_incl 1 (60 * 24 * 40)
       and amount = gen_amount in
       past (minutes minutes_ago) amount)
  and age_hours = Int.gen_incl 0 100
  and to_country = Quickcheck.Generator.of_list [ None; Some "DE"; Some "FR"; Some "NL" ]
  and is_card = Bool.quickcheck_generator
  and mcc = Quickcheck.Generator.of_list [ 5411; 7995 ]
  and channel = Quickcheck.Generator.of_list Context.Card_auth.Channel.all
  and online_enabled = Bool.quickcheck_generator in
  let country = Option.map to_country ~f:Country.of_string in
  let subject =
    if is_card
    then card ~mcc ?merchant_country:country ~channel ~online_enabled amount
    else
      transfer
        ~beneficiary:(beneficiary ~first_seen:(ago (hours age_hours)) ())
        ?country
        amount
  in
  return (context ~history subject)
;;

let%test_unit "adding a built-in rule never lowers the decision" =
  Quickcheck.test
    ~trials:2_000
    ~sexp_of:[%sexp_of: Rule_spec.t list * Rule_spec.t * Context.t]
    (Quickcheck.Generator.tuple3 (List.gen_with_length 3 gen_spec) gen_spec gen_context)
    ~f:(fun (specs, extra, ctx) ->
      let rules = List.map specs ~f:to_rule in
      let before = Engine.evaluate rules ctx in
      let after = Engine.evaluate (rules @ [ to_rule extra ]) ctx in
      [%test_pred: Severity.t * Severity.t]
        (fun (b, a) -> Severity.( >= ) a b)
        (before.severity, after.severity))
;;

let%test_unit "decision severity is the worst hit" =
  Quickcheck.test ~trials:500 ~sexp_of:[%sexp_of: Context.t] gen_context ~f:(fun ctx ->
    let d = Engine.evaluate (List.map pool ~f:to_rule) ctx in
    let worst =
      List.fold d.hits ~init:Severity.Allow ~f:(fun acc hit ->
        Severity.worst acc hit.severity)
    in
    [%test_eq: Severity.t] d.severity worst)
;;
