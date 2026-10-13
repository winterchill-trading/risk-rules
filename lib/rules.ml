open! Core

let amount_str = Money.Amount.to_string
let span_str = Time_ns.Span.to_string

(* Callers pass a limit looked up for the amount's own currency, so the comparison cannot
   fail on mismatched currencies. *)
let compare_same a b = Or_error.ok_exn (Money.Amount.compare_value a b)
let exceeds amount ~limit = compare_same amount limit > 0

let on_transfer ~name ~severity f =
  Rule.create ~name ~severity (fun (ctx : Context.t) ->
    match ctx.subject with
    | Transfer transfer -> f ctx transfer
    | Card_auth _ -> None)
;;

let on_card ~name ~severity f =
  Rule.create ~name ~severity (fun (ctx : Context.t) ->
    match ctx.subject with
    | Card_auth auth -> f ctx auth
    | Transfer _ -> None)
;;

let per_transfer_cap ?(name = "per_transfer_cap") ?(severity = Severity.Block) limits =
  on_transfer ~name ~severity (fun _ (transfer : Context.Transfer.t) ->
    let limit, note =
      Limits.limit_for limits (Money.Amount.currency (Context.Transfer.amount transfer))
    in
    Option.some_if
      (exceeds (Context.Transfer.amount transfer) ~limit)
      (sprintf
         "%s exceeds the per-transfer cap of %s%s"
         (amount_str (Context.Transfer.amount transfer))
         (amount_str limit)
         note))
;;

let same_currency_total (ctx : Context.t) ~window amount =
  let currency = Money.Amount.currency amount in
  Context.history_within ctx ~window
  |> List.filter_map ~f:(fun (past : Context.Past_transfer.t) ->
    Option.some_if
      (Money.Currency.equal (Money.Amount.currency past.amount) currency)
      past.amount)
  |> Money.Amount.sum currency
  |> Or_error.ok_exn
;;

let window_cap ~name ?(severity = Severity.Block) ~window limits =
  on_transfer ~name ~severity (fun ctx (transfer : Context.Transfer.t) ->
    let limit, note =
      Limits.limit_for limits (Money.Amount.currency (Context.Transfer.amount transfer))
    in
    let before = same_currency_total ctx ~window (Context.Transfer.amount transfer) in
    let total = Money.Amount.add_exn before (Context.Transfer.amount transfer) in
    Option.some_if
      (exceeds total ~limit)
      (sprintf
         "%s plus %s already sent in %s exceeds the cap of %s%s"
         (amount_str (Context.Transfer.amount transfer))
         (amount_str before)
         (span_str window)
         (amount_str limit)
         note))
;;

let daily_cap ?severity limits =
  window_cap ~name:"daily_cap" ?severity ~window:Time_ns.Span.day limits
;;

(* Rolling 30 days rather than the calendar month: no time zone is needed and a customer
   cannot double the limit across a month boundary. *)
let monthly_cap ?severity limits =
  window_cap ~name:"monthly_cap" ?severity ~window:(Time_ns.Span.of_day 30.) limits
;;

let velocity ?(name = "velocity") ?(severity = Severity.Review) ~max_count ~window () =
  on_transfer ~name ~severity (fun ctx _ ->
    let count = List.length (Context.history_within ctx ~window) + 1 in
    Option.some_if
      (count > max_count)
      (sprintf "%d transfers in %s (at most %d)" count (span_str window) max_count))
;;

let new_beneficiary_cooldown
  ?(name = "new_beneficiary_cooldown")
  ?(severity = Severity.Block)
  ?(exempt_trusted = false)
  ~cooldown
  ~above
  ()
  =
  on_transfer ~name ~severity (fun (ctx : Context.t) (transfer : Context.Transfer.t) ->
    let beneficiary = transfer.beneficiary in
    let beneficiary_id = Payments_core.Beneficiary.Id.to_string beneficiary.id in
    let age = Time_ns.diff ctx.now beneficiary.first_seen in
    let in_cooldown = Time_ns.Span.( < ) age cooldown in
    let limit, note =
      Limits.limit_for above (Money.Amount.currency (Context.Transfer.amount transfer))
    in
    if in_cooldown
       && exceeds (Context.Transfer.amount transfer) ~limit
       && not (exempt_trusted && beneficiary.trusted)
    then
      Some
        (sprintf
           "%s to beneficiary %s first seen %s ago; above %s during the %s cooldown%s"
           (amount_str (Context.Transfer.amount transfer))
           beneficiary_id
           (span_str (Time_ns.Span.max age Time_ns.Span.zero))
           (amount_str limit)
           (span_str cooldown)
           note)
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
  on_transfer ~name ~severity (fun ctx (transfer : Context.Transfer.t) ->
    let currency = Money.Amount.currency (Context.Transfer.amount transfer) in
    (* Unlike the caps, a missing currency switches the matching half of the heuristic
       off: "just below zero" and "a multiple of zero" mean nothing, and flagging every
       amount would bury real cases. *)
    let threshold = Limits.find threshold currency in
    let round_unit = Limits.find round_unit currency in
    let is_round amount =
      match round_unit with
      | `Missing _ -> false
      | `Configured unit ->
        Money.Amount.is_positive amount
        && Money.Amount.is_positive unit
        && Z.equal
             (Z.rem (Money.Amount.minor_units amount) (Money.Amount.minor_units unit))
             Z.zero
    in
    let just_below amount =
      match threshold with
      | `Missing _ -> false
      | `Configured line ->
        let floor = Money.Amount.mul_bps line ~bps:(10_000 - margin_bps) in
        compare_same amount floor >= 0 && compare_same amount line < 0
    in
    let suspicious amount =
      Money.Currency.equal (Money.Amount.currency amount) currency
      && (is_round amount || just_below amount)
    in
    if not (suspicious (Context.Transfer.amount transfer))
    then None
    else (
      let earlier =
        List.count (Context.history_within ctx ~window) ~f:(fun past ->
          suspicious past.amount)
      in
      let count = earlier + 1 in
      Option.some_if
        (count >= min_count)
        (sprintf
           "%d round or just-below-threshold transfers in %s (this one %s)"
           count
           (span_str window)
           (amount_str (Context.Transfer.amount transfer)))))
;;

let country_rule ~name ~severity ~label countries =
  let listed = Country.Set.of_list countries in
  Rule.create ~name ~severity (fun ctx ->
    match List.filter (Context.countries ctx) ~f:(Set.mem listed) with
    | [] -> None
    | hits ->
      Some
        (sprintf
           "%s: %s"
           label
           (String.concat ~sep:", " (List.map hits ~f:Country.to_string))))
;;

let blocked_countries ?(name = "blocked_country") ?(severity = Severity.Block) countries =
  country_rule ~name ~severity ~label:"blocked country" countries
;;

let high_risk_countries
  ?(name = "high_risk_country")
  ?(severity = Severity.Review)
  countries
  =
  country_rule ~name ~severity ~label:"high-risk country" countries
;;

let unverified_self_hosted_wallet
  ?(name = "travel_rule_self_hosted")
  ?(severity = Severity.Review)
  ~above
  ()
  =
  on_transfer ~name ~severity (fun _ (transfer : Context.Transfer.t) ->
    match transfer.wallet with
    | Some { self_hosted = true; ownership_verified = false } ->
      let limit, note =
        Limits.limit_for above (Money.Amount.currency (Context.Transfer.amount transfer))
      in
      Option.some_if
        (exceeds (Context.Transfer.amount transfer) ~limit)
        (sprintf
           "%s to an unverified self-hosted wallet above %s%s: collect travel-rule \
            originator and beneficiary information or proof of ownership"
           (amount_str (Context.Transfer.amount transfer))
           (amount_str limit)
           note)
    | Some _ | None -> None)
;;

let blocked_mccs ?(name = "blocked_mcc") ?(severity = Severity.Block) mccs =
  let listed = Mcc.Set.of_list mccs in
  on_card ~name ~severity (fun _ (auth : Context.Card_auth.t) ->
    Option.some_if
      (Set.mem listed auth.mcc)
      (sprintf "merchant category %s is blocked" (Mcc.to_string auth.mcc)))
;;

let online_toggle ?(name = "online_toggle") ?(severity = Severity.Block) () =
  on_card ~name ~severity (fun _ (auth : Context.Card_auth.t) ->
    match auth.channel, auth.online_enabled with
    | Online, false -> Some "online payments are switched off for this card"
    | (Online | In_person | Atm), _ -> None)
;;
