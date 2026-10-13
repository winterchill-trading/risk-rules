open! Core

let amount_str = Money.Amount.to_string
let span_str = Time_ns.Span.to_string

(* Callers pass a limit looked up for the amount's own currency, so the comparison cannot
   fail on mismatched currencies. *)
let compare_same a b = Or_error.ok_exn (Money.Amount.compare_value a b)
let exceeds amount ~limit = compare_same amount limit > 0

(* A rule with a fixed severity and code whose check returns the reason and the evidence.
   Built on [create_graded] so evidence can be computed in the same pass as the reason. *)
let make ~name ~severity ~code check =
  Rule.create_graded ~name ~max_severity:severity (fun ctx ->
    Option.map (check ctx) ~f:(fun (reason, evidence) ->
      { Rule.Outcome.severity; code; reason; evidence }))
;;

let on_transfer ~name ~severity ~code f =
  make ~name ~severity ~code (fun (ctx : Context.t) ->
    match ctx.subject with
    | Transfer transfer -> f ctx transfer
    | Card_auth _ -> None)
;;

let on_card ~name ~severity ~code f =
  make ~name ~severity ~code (fun (ctx : Context.t) ->
    match ctx.subject with
    | Card_auth auth -> f ctx auth
    | Transfer _ -> None)
;;

let limit_evidence ~amount ~limit ~note =
  [ "amount", amount_str amount; "limit", amount_str limit ]
  @ if String.is_empty note then [] else [ "limit_missing", "true" ]
;;

let per_transfer_cap ?(name = "per_transfer_cap") ?(severity = Severity.Block) limits =
  on_transfer ~name ~severity ~code:Limit_per_transfer (fun _ transfer ->
    let amount = Context.Transfer.amount transfer in
    let limit, note = Limits.limit_for limits (Money.Amount.currency amount) in
    Option.some_if
      (exceeds amount ~limit)
      ( sprintf
          "%s exceeds the per-transfer cap of %s%s"
          (amount_str amount)
          (amount_str limit)
          note
      , limit_evidence ~amount ~limit ~note ))
;;

let same_currency_total (pasts : Context.Past_transfer.t list) currency =
  List.filter_map pasts ~f:(fun past ->
    Option.some_if
      (Money.Currency.equal (Money.Amount.currency past.amount) currency)
      past.amount)
  |> Money.Amount.sum currency
  |> Or_error.ok_exn
;;

let window_cap_with_code ~code ~name ~severity ~window limits =
  on_transfer ~name ~severity ~code (fun ctx transfer ->
    let amount = Context.Transfer.amount transfer in
    let currency = Money.Amount.currency amount in
    let limit, note = Limits.limit_for limits currency in
    let before = same_currency_total (Context.history_within ctx ~window) currency in
    let total = Money.Amount.add_exn before amount in
    Option.some_if
      (exceeds total ~limit)
      ( sprintf
          "%s plus %s already sent in %s exceeds the cap of %s%s"
          (amount_str amount)
          (amount_str before)
          (span_str window)
          (amount_str limit)
          note
      , limit_evidence ~amount ~limit ~note
        @ [ "window", span_str window; "already_sent", amount_str before ] ))
;;

let window_cap ~name ?(severity = Severity.Block) ~window limits =
  window_cap_with_code ~code:Limit_window ~name ~severity ~window limits
;;

let daily_cap ?(severity = Severity.Block) limits =
  window_cap_with_code
    ~code:Limit_daily
    ~name:"daily_cap"
    ~severity
    ~window:Time_ns.Span.day
    limits
;;

(* Rolling 30 days rather than the calendar month: no time zone is needed and a customer
   cannot double the limit across a month boundary. *)
let monthly_cap ?(severity = Severity.Block) limits =
  window_cap_with_code
    ~code:Limit_monthly
    ~name:"monthly_cap"
    ~severity
    ~window:(Time_ns.Span.of_day 30.)
    limits
;;

let velocity ?(name = "velocity") ?(severity = Severity.Review) ~max_count ~window () =
  on_transfer ~name ~severity ~code:Velocity_out (fun ctx _ ->
    let count = List.length (Context.history_within ctx ~window) + 1 in
    Option.some_if
      (count > max_count)
      ( sprintf "%d transfers in %s (at most %d)" count (span_str window) max_count
      , [ "count", Int.to_string count
        ; "max_count", Int.to_string max_count
        ; "window", span_str window
        ] ))
;;

let beneficiary_age (ctx : Context.t) (transfer : Context.Transfer.t) =
  Time_ns.Span.max
    (Time_ns.diff ctx.now transfer.beneficiary.first_seen)
    Time_ns.Span.zero
;;

let beneficiary_id (transfer : Context.Transfer.t) =
  Payments_core.Beneficiary.Id.to_string transfer.beneficiary.id
;;

let new_beneficiary_cooldown
  ?(name = "new_beneficiary_cooldown")
  ?(severity = Severity.Block)
  ?(exempt_trusted = false)
  ~cooldown
  ~above
  ()
  =
  on_transfer ~name ~severity ~code:New_beneficiary_cooldown (fun ctx transfer ->
    let amount = Context.Transfer.amount transfer in
    let age = beneficiary_age ctx transfer in
    let limit, note = Limits.limit_for above (Money.Amount.currency amount) in
    if Time_ns.Span.( < ) age cooldown
       && exceeds amount ~limit
       && not (exempt_trusted && transfer.beneficiary.trusted)
    then
      Some
        ( sprintf
            "%s to beneficiary %s first seen %s ago; above %s during the %s cooldown%s"
            (amount_str amount)
            (beneficiary_id transfer)
            (span_str age)
            (amount_str limit)
            (span_str cooldown)
            note
        , limit_evidence ~amount ~limit ~note
          @ [ "beneficiary", beneficiary_id transfer
            ; "beneficiary_age", span_str age
            ; "cooldown", span_str cooldown
            ] )
    else None)
;;

let structuring
  ?(name = "structuring")
  ?(severity = Severity.Review)
  ~threshold
  ?(margin_bps = 1_000)
  ~round_unit
  ~min_count
  ~window
  ()
  =
  on_transfer ~name ~severity ~code:Structuring (fun ctx transfer ->
    let amount = Context.Transfer.amount transfer in
    let currency = Money.Amount.currency amount in
    (* Unlike the caps, a missing currency switches the matching half of the heuristic
       off: "just below zero" and "a multiple of zero" mean nothing, and flagging every
       amount would bury real cases. *)
    let threshold = Limits.find threshold currency in
    let round_unit = Limits.find round_unit currency in
    let is_round a =
      match round_unit with
      | `Missing _ -> false
      | `Configured unit ->
        Money.Amount.is_positive a
        && Money.Amount.is_positive unit
        && Z.equal
             (Z.rem (Money.Amount.minor_units a) (Money.Amount.minor_units unit))
             Z.zero
    in
    let just_below a =
      match threshold with
      | `Missing _ -> false
      | `Configured line ->
        let floor = Money.Amount.mul_bps line ~bps:(10_000 - margin_bps) in
        compare_same a floor >= 0 && compare_same a line < 0
    in
    let suspicious a =
      Money.Currency.equal (Money.Amount.currency a) currency
      && (is_round a || just_below a)
    in
    if not (suspicious amount)
    then None
    else (
      let earlier =
        List.count (Context.history_within ctx ~window) ~f:(fun past ->
          suspicious past.amount)
      in
      let count = earlier + 1 in
      Option.some_if
        (count >= min_count)
        ( sprintf
            "%d round or just-below-threshold transfers in %s (this one %s)"
            count
            (span_str window)
            (amount_str amount)
        , [ "amount", amount_str amount
          ; "count", Int.to_string count
          ; "min_count", Int.to_string min_count
          ; "window", span_str window
          ] )))
;;

let mule_pass_through
  ?(name = "mule_pass_through")
  ?(severity = Severity.Review)
  ~window
  ~min_incoming
  ?(ratio_bps = 8_000)
  ()
  =
  on_transfer ~name ~severity ~code:Mule_pass_through (fun ctx transfer ->
    let amount = Context.Transfer.amount transfer in
    let currency = Money.Amount.currency amount in
    let incoming = same_currency_total (Context.incoming_within ctx ~window) currency in
    let outgoing =
      Money.Amount.add_exn
        (same_currency_total (Context.history_within ctx ~window) currency)
        amount
    in
    let floor, note = Limits.limit_for min_incoming currency in
    (* outgoing * 10_000 >= incoming * ratio_bps, in exact minor units. *)
    let passes_through =
      Z.geq
        (Z.mul (Money.Amount.minor_units outgoing) (Z.of_int 10_000))
        (Z.mul (Money.Amount.minor_units incoming) (Z.of_int ratio_bps))
    in
    Option.some_if
      (Money.Amount.is_positive incoming
       && compare_same incoming floor >= 0
       && passes_through)
      ( sprintf
          "%s received and %s sent on (this one included) within %s%s"
          (amount_str incoming)
          (amount_str outgoing)
          (span_str window)
          note
      , [ "incoming", amount_str incoming
        ; "outgoing", amount_str outgoing
        ; "ratio_bps", Int.to_string ratio_bps
        ; "window", span_str window
        ] ))
;;

(* Shared by [account_takeover] and [sca_tra] so both count the same signals. *)
let takeover_signals (ctx : Context.t) ~recent =
  let within time = Time_ns.Span.( < ) (Time_ns.diff ctx.now time) recent in
  List.filter_opt
    [ Option.some_if ctx.session.new_device "new_device"
    ; (match ctx.geo.ip_country, ctx.geo.residence with
       | Some ip, Some home when not (Country.equal ip home) ->
         Some "ip_outside_residence"
       | _ -> None)
    ; Option.bind ctx.session.credentials_changed_at ~f:(fun at ->
        Option.some_if (within at) "credentials_changed")
    ; Option.bind (Context.transfer ctx) ~f:(fun t ->
        Option.some_if (within t.beneficiary.first_seen) "new_beneficiary")
    ]
;;

let account_takeover
  ?(name = "account_takeover")
  ?(severity = Severity.Review)
  ?(min_signals = 2)
  ~recent
  ()
  =
  make ~name ~severity ~code:Account_takeover_signals (fun (ctx : Context.t) ->
    let remote =
      match ctx.subject with
      | Transfer _ -> true
      | Card_auth { channel = Online; _ } -> true
      | Card_auth { channel = In_person | Atm; _ } -> false
    in
    let signals = takeover_signals ctx ~recent in
    Option.some_if
      (remote && List.length signals >= min_signals)
      ( sprintf
          "%d account takeover signals: %s"
          (List.length signals)
          (String.concat ~sep:", " signals)
      , List.map signals ~f:(fun s -> "signal", s)
        @ [ "min_signals", Int.to_string min_signals; "recent", span_str recent ] ))
;;

let app_fraud
  ?(name = "app_fraud")
  ?(severity = Severity.Review)
  ~new_within
  ?(balance_share_bps = 8_000)
  ()
  =
  on_transfer ~name ~severity ~code:App_new_beneficiary_balance (fun ctx transfer ->
    let amount = Context.Transfer.amount transfer in
    let age = beneficiary_age ctx transfer in
    match Context.balance ctx (Money.Amount.currency amount) with
    | None -> None
    | Some balance ->
      let large_share =
        Money.Amount.is_positive balance
        && Z.geq
             (Z.mul (Money.Amount.minor_units amount) (Z.of_int 10_000))
             (Z.mul (Money.Amount.minor_units balance) (Z.of_int balance_share_bps))
      in
      Option.some_if
        (Time_ns.Span.( < ) age new_within && large_share)
        ( sprintf
            "%s of an available %s to beneficiary %s first seen %s ago"
            (amount_str amount)
            (amount_str balance)
            (beneficiary_id transfer)
            (span_str age)
        , [ "amount", amount_str amount
          ; "balance", amount_str balance
          ; "beneficiary_age", span_str age
          ; "balance_share_bps", Int.to_string balance_share_bps
          ] ))
;;

let country_rule ~name ~severity ~code ~label countries =
  let listed = Country.Set.of_list countries in
  make ~name ~severity ~code (fun ctx ->
    match List.filter (Context.countries ctx) ~f:(Set.mem listed) with
    | [] -> None
    | hits ->
      Some
        ( sprintf
            "%s: %s"
            label
            (String.concat ~sep:", " (List.map hits ~f:Country.to_string))
        , List.map hits ~f:(fun c -> "country", Country.to_string c) ))
;;

let blocked_countries ?(name = "blocked_country") ?(severity = Severity.Block) countries =
  country_rule ~name ~severity ~code:Geo_blocked ~label:"blocked country" countries
;;

let high_risk_countries
  ?(name = "high_risk_country")
  ?(severity = Severity.Review)
  countries
  =
  country_rule ~name ~severity ~code:Geo_high_risk ~label:"high-risk country" countries
;;

let unverified_self_hosted_wallet
  ?(name = "travel_rule_self_hosted")
  ?(severity = Severity.Review)
  ~above
  ()
  =
  on_transfer ~name ~severity ~code:Travel_rule_self_hosted (fun _ transfer ->
    match transfer.wallet with
    | Some { self_hosted = true; ownership_verified = false } ->
      let amount = Context.Transfer.amount transfer in
      let limit, note = Limits.limit_for above (Money.Amount.currency amount) in
      Option.some_if
        (exceeds amount ~limit)
        ( sprintf
            "%s to an unverified self-hosted wallet above %s%s: collect travel-rule \
             originator and beneficiary information or proof of ownership"
            (amount_str amount)
            (amount_str limit)
            note
        , limit_evidence ~amount ~limit ~note )
    | Some _ | None -> None)
;;

let blocked_mccs ?(name = "blocked_mcc") ?(severity = Severity.Block) mccs =
  let listed = Mcc.Set.of_list mccs in
  on_card ~name ~severity ~code:Card_mcc_blocked (fun _ auth ->
    Option.some_if
      (Set.mem listed auth.mcc)
      ( sprintf "merchant category %s is blocked" (Mcc.to_string auth.mcc)
      , [ "mcc", Mcc.to_string auth.mcc ] ))
;;

let online_toggle ?(name = "online_toggle") ?(severity = Severity.Block) () =
  on_card ~name ~severity ~code:Card_online_disabled (fun _ auth ->
    match auth.channel, auth.online_enabled with
    | Online, false -> Some ("online payments are switched off for this card", [])
    | (Online | In_person | Atm), _ -> None)
;;

module Thresholds = struct
  type t =
    { challenge_at : float option [@sexp.option]
    ; review_at : float option [@sexp.option]
    ; block_at : float option [@sexp.option]
    }
  [@@deriving sexp, compare, equal]

  let validate { challenge_at; review_at; block_at } =
    let present = List.filter_opt [ challenge_at; review_at; block_at ] in
    if List.exists present ~f:(fun x -> Float.is_nan x || Float.(x < 0. || x > 1.))
    then Or_error.error_string "score thresholds must be within [0, 1]"
    else if not (List.is_sorted present ~compare:Float.compare)
    then
      Or_error.error_string "score thresholds must satisfy challenge <= review <= block"
    else Ok ()
  ;;

  let severity_for t score =
    List.find_map
      [ t.block_at, Severity.Block; t.review_at, Review; t.challenge_at, Challenge ]
      ~f:(fun (threshold, severity) ->
        Option.bind threshold ~f:(fun at -> Option.some_if Float.(score >= at) severity))
  ;;
end

let score_evidence model (score : Model.Score.t) =
  [ "model", Model.name model
  ; "model_version", Model.version model
  ; "score", sprintf "%.4f" score.value
  ]
  @ List.map score.reasons ~f:(fun (code, contribution) ->
    "model_reason", sprintf "%s=%.4f" code contribution)
;;

let model_score ?(name = "model_score") model thresholds =
  Rule.create_graded ~name ~max_severity:Block (fun ctx ->
    let score = Model.score model (Features.of_context ctx) in
    Option.map (Thresholds.severity_for thresholds score.value) ~f:(fun severity ->
      { Rule.Outcome.severity
      ; code = Score_high
      ; reason =
          sprintf
            "%s %s scored %.4f%s"
            (Model.name model)
            (Model.version model)
            score.value
            (match score.reasons with
             | [] -> ""
             | reasons ->
               sprintf
                 " (top reasons: %s)"
                 (String.concat ~sep:", " (List.map reasons ~f:fst)))
      ; evidence = score_evidence model score
      }))
;;

module Tra = struct
  type scheme =
    | Credit_transfer
    | Card_not_present
  [@@deriving sexp, compare, equal, enumerate]

  let eur s = Money.Amount.of_string (s ^ " EUR")

  (* RTS (EU) 2018/389, annex: exemption threshold value -> reference fraud rate. Rates in
     parts per million (0.015% = 150 ppm). *)
  let reference_bands = function
    | Credit_transfer -> [ eur "100.00", 150; eur "250.00", 100; eur "500.00", 50 ]
    | Card_not_present -> [ eur "100.00", 1_300; eur "250.00", 600; eur "500.00", 100 ]
  ;;

  let threshold scheme ~observed_fraud_rate_ppm =
    List.filter (reference_bands scheme) ~f:(fun (_, reference) ->
      observed_fraud_rate_ppm <= reference)
    |> List.map ~f:fst
    |> List.max_elt ~compare:Money.Amount.compare
  ;;
end

let sca_tra
  ?(name = "sca_tra")
  ?(severity = Severity.Challenge)
  ~scheme
  ~observed_fraud_rate_ppm
  ?(trusted_beneficiaries_exempt = true)
  ?(recent = Time_ns.Span.day)
  ?model
  ()
  =
  make ~name ~severity ~code:Sca_required (fun (ctx : Context.t) ->
    let applies, trusted =
      match (scheme : Tra.scheme), ctx.subject with
      | Credit_transfer, Transfer t -> true, t.beneficiary.trusted
      | Card_not_present, Card_auth { channel = Online; _ } -> true, false
      | Credit_transfer, Card_auth _
      | Card_not_present, Transfer _
      | Card_not_present, Card_auth { channel = In_person | Atm; _ } -> false, false
    in
    if (not applies) || (trusted_beneficiaries_exempt && trusted)
    then None
    else (
      let amount = Context.amount ctx in
      let tra_limit = Tra.threshold scheme ~observed_fraud_rate_ppm in
      let signals = takeover_signals ctx ~recent in
      let score =
        Option.map model ~f:(fun (model, max_score) ->
          model, max_score, Model.score model (Features.of_context ctx))
      in
      (* Every reason the exemption fails, so the audit log shows all of them, not just
         the first. *)
      let blockers =
        List.filter_opt
          [ (match tra_limit with
             | None ->
               Some
                 (sprintf
                    "observed fraud rate %d ppm is above every reference rate"
                    observed_fraud_rate_ppm)
             | Some limit ->
               if not
                    (Money.Currency.equal
                       (Money.Amount.currency amount)
                       Money.Currency.eur)
               then Some "not in EUR (no conversion to the EUR thresholds)"
               else if exceeds amount ~limit
               then
                 Some
                   (sprintf
                      "%s is above the %s exemption threshold"
                      (amount_str amount)
                      (amount_str limit))
               else None)
          ; (match signals with
             | [] -> None
             | signals -> Some ("risk signals: " ^ String.concat ~sep:", " signals))
          ; Option.bind score ~f:(fun (_, max_score, (score : Model.Score.t)) ->
              Option.some_if
                Float.(score.value >= max_score)
                (sprintf "score %.4f at or above %.4f" score.value max_score))
          ]
      in
      match blockers with
      | [] -> None
      | blockers ->
        Some
          ( "no SCA exemption: " ^ String.concat ~sep:"; " blockers
          , [ "scheme", Sexp.to_string [%sexp (scheme : Tra.scheme)]
            ; "observed_fraud_rate_ppm", Int.to_string observed_fraud_rate_ppm
            ; "tra_threshold", Option.value_map tra_limit ~default:"none" ~f:amount_str
            ]
            @ List.map signals ~f:(fun s -> "signal", s)
            @ Option.value_map score ~default:[] ~f:(fun (model, _, s) ->
              score_evidence model s) )))
;;
