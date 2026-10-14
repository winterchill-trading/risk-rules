open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Stable = struct
  module V1 = struct
    type t =
      { schema_version : int
      ; is_card : bool
      ; rail : string
      ; card_channel : string option
      ; currency : string
      ; amount : float
      ; amount_is_round : bool
      ; balance : float option
      ; amount_to_balance : float option
      ; beneficiary_age_hours : float option
      ; beneficiary_trusted : bool option
      ; counterparty_country_is_residence : bool option
      ; self_hosted_unverified : bool
      ; mcc : int option
      ; out_count_1h : int
      ; out_count_24h : int
      ; out_sum_24h : float
      ; out_sum_30d : float
      ; out_distinct_beneficiaries_24h : int
      ; in_count_24h : int
      ; in_sum_24h : float
      ; pass_through_ratio_24h : float option
      ; new_device : bool
      ; ip_country_is_residence : bool option
      ; hours_since_credentials_change : float option
      ; account_age_days : float option
      ; hour_of_day_utc : int
      ; log1p_amount : float
      ; is_weekend : bool
      ; out_count_7d : int
      ; out_sum_1h : float
      ; out_sum_7d : float
      ; amount_over_mean_30d : float option
      ; in_distinct_senders_24h : int
      ; minutes_since_last_inbound : float option
      ; failed_sca_24h : int
      ; payee_check : string option
      ; card_auths_10m : int
      ; card_declines_10m : int
      }
    [@@deriving bin_io, sexp, compare, equal, yojson]
  end
end

type t = Stable.V1.t [@@deriving sexp, compare, equal, yojson]

let schema_version = 1
let major amount = Q.to_float (Money.Amount.to_q amount)
let hours span = Time_ns.Span.to_hr span

let same_currency currency (pasts : Context.Past_transfer.t list) =
  List.filter pasts ~f:(fun past ->
    Money.Currency.equal (Money.Amount.currency past.amount) currency)
;;

let sum pasts =
  List.fold pasts ~init:0. ~f:(fun acc (past : Context.Past_transfer.t) ->
    acc +. major past.amount)
;;

let opt_equal a b =
  match a, b with
  | Some a, Some b -> Some (Country.equal a b)
  | None, _ | _, None -> None
;;

let of_context (ctx : Context.t) =
  let amount_money = Context.amount ctx in
  let currency = Money.Amount.currency amount_money in
  let amount = major amount_money in
  let balance = Option.map (Context.balance ctx currency) ~f:major in
  let day = Time_ns.Span.day in
  let out_1h = Context.history_within ctx ~window:Time_ns.Span.hour in
  let out_24h = Context.history_within ctx ~window:day in
  let out_30d = Context.history_within ctx ~window:(Time_ns.Span.of_day 30.) in
  let in_24h = Context.incoming_within ctx ~window:day in
  let out_7d = Context.history_within ctx ~window:(Time_ns.Span.of_day 7.) in
  let card_10m = Context.card_history_within ctx ~window:(Time_ns.Span.of_min 10.) in
  let out_sum_24h = sum (same_currency currency out_24h) in
  let in_sum_24h = sum (same_currency currency in_24h) in
  let transfer = Context.transfer ctx in
  let card = Context.card_auth ctx in
  let counterparty_country =
    match ctx.subject with
    | Transfer t -> t.beneficiary_country
    | Card_auth a -> a.merchant_country
  in
  let since time = hours (Time_ns.diff ctx.now time) in
  { Stable.V1.schema_version
  ; is_card = Option.is_some card
  ; rail =
      (match transfer with
       | Some t -> Payments_core.Rail.to_string t.draft.rail
       | None -> "card")
  ; card_channel =
      Option.map card ~f:(fun a ->
        Sexp.to_string [%sexp (a.channel : Context.Card_auth.Channel.t)])
  ; currency = Money.Currency.to_string currency
  ; amount
  ; amount_is_round =
      (* 100 major units in any currency: a coarse signal, kept simple on purpose so the
         training pipeline can recompute it from the amount. *)
      Float.( > ) amount 0. && Float.equal (Float.mod_float amount 100.) 0.
  ; balance
  ; amount_to_balance =
      Option.bind balance ~f:(fun b -> Option.some_if Float.(b > 0.) (amount /. b))
  ; beneficiary_age_hours =
      Option.map transfer ~f:(fun t -> since t.beneficiary.first_seen)
  ; beneficiary_trusted = Option.map transfer ~f:(fun t -> t.beneficiary.trusted)
  ; counterparty_country_is_residence = opt_equal counterparty_country ctx.geo.residence
  ; self_hosted_unverified =
      (match Option.bind transfer ~f:(fun t -> t.wallet) with
       | Some { self_hosted = true; ownership_verified = false } -> true
       | Some _ | None -> false)
  ; mcc = Option.map card ~f:(fun a -> Mcc.to_int a.mcc)
  ; out_count_1h = List.length out_1h
  ; out_count_24h = List.length out_24h
  ; out_sum_24h
  ; out_sum_30d = sum (same_currency currency out_30d)
  ; out_distinct_beneficiaries_24h =
      List.filter_map out_24h ~f:(fun p -> p.beneficiary)
      |> List.dedup_and_sort ~compare:Payments_core.Beneficiary.Id.compare
      |> List.length
  ; in_count_24h = List.length in_24h
  ; in_sum_24h
  ; pass_through_ratio_24h =
      Option.some_if Float.(in_sum_24h > 0.) ((out_sum_24h +. amount) /. in_sum_24h)
  ; new_device = ctx.session.new_device
  ; ip_country_is_residence = opt_equal ctx.geo.ip_country ctx.geo.residence
  ; hours_since_credentials_change =
      Option.map ctx.session.credentials_changed_at ~f:since
  ; account_age_days =
      Option.map ctx.session.account_opened_at ~f:(fun opened ->
        Time_ns.Span.to_day (Time_ns.diff ctx.now opened))
  ; log1p_amount = Float.log1p amount
  ; is_weekend =
      (match Date.day_of_week (Time_ns.to_date ctx.now ~zone:Time_float.Zone.utc) with
       | Sat | Sun -> true
       | Mon | Tue | Wed | Thu | Fri -> false)
  ; out_count_7d = List.length out_7d
  ; out_sum_1h = sum (same_currency currency out_1h)
  ; out_sum_7d = sum (same_currency currency out_7d)
  ; amount_over_mean_30d =
      (match same_currency currency out_30d with
       | [] -> None
       | pasts ->
         let mean = sum pasts /. Float.of_int (List.length pasts) in
         Option.some_if Float.(mean > 0.) (amount /. mean))
  ; in_distinct_senders_24h =
      List.filter_map in_24h ~f:(fun p -> p.sender)
      |> List.dedup_and_sort ~compare:String.compare
      |> List.length
  ; minutes_since_last_inbound =
      List.map ctx.incoming ~f:(fun p -> p.at)
      |> List.filter ~f:(fun at -> Time_ns.( <= ) at ctx.now)
      |> List.max_elt ~compare:Time_ns.compare
      |> Option.map ~f:(fun at -> Time_ns.Span.to_min (Time_ns.diff ctx.now at))
  ; failed_sca_24h = ctx.session.failed_sca_24h
  ; payee_check =
      Option.bind transfer ~f:(fun t ->
        Option.map t.beneficiary.payee_check ~f:(fun check ->
          match (check : Payments_core.Beneficiary.Payee_check.t) with
          | Match -> "Match"
          | Close_match _ -> "Close_match"
          | No_match -> "No_match"
          | Not_possible -> "Not_possible"
          | Account_not_found -> "Account_not_found"
          | Unavailable -> "Unavailable"))
  ; card_auths_10m = List.length card_10m
  ; card_declines_10m = List.count card_10m ~f:(fun a -> not a.approved)
  ; hour_of_day_utc =
      Time_ns.to_ofday ctx.now ~zone:Time_float.Zone.utc
      |> Time_ns.Ofday.to_span_since_start_of_day
      |> Time_ns.Span.to_hr
      |> Float.iround_down_exn
  }
;;

let schema =
  [ "schema_version", "feature schema version"
  ; "is_card", "card authorisation rather than a transfer"
  ; "rail", "payments-core rail, or card"
  ; "card_channel", "card channel: Online, In_person, Atm"
  ; "currency", "currency of the amount"
  ; "amount", "amount in major units"
  ; "amount_is_round", "positive multiple of 100 major units"
  ; "balance", "available balance in the currency"
  ; "amount_to_balance", "amount / balance"
  ; "beneficiary_age_hours", "hours since the beneficiary was first used"
  ; "beneficiary_trusted", "beneficiary confirmed as trusted"
  ; ( "counterparty_country_is_residence"
    , "beneficiary or merchant country is the residence" )
  ; "self_hosted_unverified", "crypto to an unproven self-hosted wallet"
  ; "mcc", "merchant category code"
  ; "out_count_1h", "outgoing transfers in the last hour"
  ; "out_count_24h", "outgoing transfers in the last 24 hours"
  ; "out_sum_24h", "outgoing total in the currency, last 24 hours"
  ; "out_sum_30d", "outgoing total in the currency, last 30 days"
  ; "out_distinct_beneficiaries_24h", "distinct beneficiaries paid in the last 24 hours"
  ; "in_count_24h", "incoming transfers in the last 24 hours"
  ; "in_sum_24h", "incoming total in the currency, last 24 hours"
  ; "pass_through_ratio_24h", "(outgoing 24h + amount) / incoming 24h"
  ; "new_device", "first request from this device"
  ; "ip_country_is_residence", "request IP country is the residence"
  ; "hours_since_credentials_change", "hours since the last credential change"
  ; "account_age_days", "days since the account was opened"
  ; "hour_of_day_utc", "hour of the request, UTC"
  ; "log1p_amount", "log (1 + amount)"
  ; "is_weekend", "Saturday or Sunday, UTC"
  ; "out_count_7d", "outgoing transfers in the last 7 days"
  ; "out_sum_1h", "outgoing total in the currency, last hour"
  ; "out_sum_7d", "outgoing total in the currency, last 7 days"
  ; "amount_over_mean_30d", "amount / mean outgoing amount over 30 days"
  ; "in_distinct_senders_24h", "distinct payers in the last 24 hours"
  ; "minutes_since_last_inbound", "minutes since the last incoming transfer"
  ; "failed_sca_24h", "failed strong authentication attempts, last 24 hours"
  ; "payee_check", "verification of payee result"
  ; "card_auths_10m", "earlier authorisations on the card, last 10 minutes"
  ; "card_declines_10m", "declined authorisations on the card, last 10 minutes"
  ]
;;

let of_bool b = if b then 1. else 0.
let of_opt f = Option.value_map ~default:Float.nan ~f

let to_floats (t : t) =
  [ "is_card", of_bool t.is_card
  ; "amount", t.amount
  ; "amount_is_round", of_bool t.amount_is_round
  ; "balance", of_opt Fn.id t.balance
  ; "amount_to_balance", of_opt Fn.id t.amount_to_balance
  ; "beneficiary_age_hours", of_opt Fn.id t.beneficiary_age_hours
  ; "beneficiary_trusted", of_opt of_bool t.beneficiary_trusted
  ; ( "counterparty_country_is_residence"
    , of_opt of_bool t.counterparty_country_is_residence )
  ; "self_hosted_unverified", of_bool t.self_hosted_unverified
  ; "mcc", of_opt Float.of_int t.mcc
  ; "out_count_1h", Float.of_int t.out_count_1h
  ; "out_count_24h", Float.of_int t.out_count_24h
  ; "out_sum_24h", t.out_sum_24h
  ; "out_sum_30d", t.out_sum_30d
  ; "out_distinct_beneficiaries_24h", Float.of_int t.out_distinct_beneficiaries_24h
  ; "in_count_24h", Float.of_int t.in_count_24h
  ; "in_sum_24h", t.in_sum_24h
  ; "pass_through_ratio_24h", of_opt Fn.id t.pass_through_ratio_24h
  ; "new_device", of_bool t.new_device
  ; "ip_country_is_residence", of_opt of_bool t.ip_country_is_residence
  ; "hours_since_credentials_change", of_opt Fn.id t.hours_since_credentials_change
  ; "account_age_days", of_opt Fn.id t.account_age_days
  ; "hour_of_day_utc", Float.of_int t.hour_of_day_utc
  ; "log1p_amount", t.log1p_amount
  ; "is_weekend", of_bool t.is_weekend
  ; "out_count_7d", Float.of_int t.out_count_7d
  ; "out_sum_1h", t.out_sum_1h
  ; "out_sum_7d", t.out_sum_7d
  ; "amount_over_mean_30d", of_opt Fn.id t.amount_over_mean_30d
  ; "in_distinct_senders_24h", Float.of_int t.in_distinct_senders_24h
  ; "minutes_since_last_inbound", of_opt Fn.id t.minutes_since_last_inbound
  ; "failed_sca_24h", Float.of_int t.failed_sca_24h
  ; "card_auths_10m", Float.of_int t.card_auths_10m
  ; "card_declines_10m", Float.of_int t.card_declines_10m
  ]
;;

let numeric_names =
  let categorical =
    [ "schema_version"; "rail"; "card_channel"; "currency"; "payee_check" ]
  in
  List.filter_map schema ~f:(fun (name, _) ->
    Option.some_if (not (List.mem categorical name ~equal:String.equal)) name)
;;

let to_json t = Yojson.Safe.to_string (yojson_of_t t)

let of_json s =
  Or_error.try_with (fun () ->
    let t = t_of_yojson (Yojson.Safe.from_string s) in
    if t.schema_version <> schema_version
    then
      raise_s
        [%message
          "features: schema version mismatch"
            ~expected:(schema_version : int)
            ~got:(t.schema_version : int)];
    t)
;;
