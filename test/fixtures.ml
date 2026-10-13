open! Core
open Risk_rules

let t0 = Time_ns.of_string_with_utc_offset "2026-10-13 12:00:00Z"
let minutes n = Time_ns.Span.of_min (Float.of_int n)
let hours n = Time_ns.Span.of_hr (Float.of_int n)
let ago span = Time_ns.sub t0 span
let eur s = Money.Amount.of_string (s ^ " EUR")
let btc s = Money.Amount.of_string (s ^ " BTC")
let limits = Limits.create_exn
let country = Country.of_string

let beneficiary
  ?(id = "ben-1")
  ?country
  ?(first_seen = ago (hours (24 * 90)))
  ?(trusted = true)
  ?wallet
  ()
  =
  { Context.Beneficiary.id; country; first_seen; trusted; wallet }
;;

let transfer
  ?(id = "tr-1")
  ?(rail = Payments_core.Rail.Sepa_instant)
  ?(beneficiary = beneficiary ())
  amount
  =
  Context.Subject.Transfer { Context.Transfer.id; amount; rail; beneficiary }
;;

let card
  ?(id = "auth-1")
  ?(mcc = 5411)
  ?merchant_country
  ?(channel = Context.Card_auth.Channel.In_person)
  ?(online_enabled = true)
  amount
  =
  Context.Subject.Card_auth
    { Context.Card_auth.id
    ; amount
    ; mcc = Mcc.of_int_exn mcc
    ; merchant_country
    ; channel
    ; online_enabled
    }
;;

let past ?(beneficiary_id = "ben-1") span amount =
  { Context.Past_transfer.at = ago span; amount; beneficiary_id }
;;

let context
  ?(tier = "basic")
  ?(history = [])
  ?(geo = Context.Geo.unknown)
  ?(balances = [ eur "10000.00" ])
  subject
  =
  { Context.customer = "cust-1"
  ; tier = Tier.of_string tier
  ; now = t0
  ; balances
  ; subject
  ; history
  ; geo
  }
;;

(* Prints the rule's verdict: "-" when it stays silent. *)
let check rule ctx =
  match Rule.check rule ctx with
  | None -> print_endline "-"
  | Some hit -> printf "%s: %s\n" (Severity.to_string hit.severity) hit.reason
;;
