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

(* Beneficiaries and drafts are real payments-core values, so these tests also check that
   the context binds to them as the API layer will. *)
let beneficiary
  ?(id = "ben-1")
  ?(rail = Payments_core.Rail.Sepa_instant)
  ?(destination = "DE89370400440532013000")
  ?(first_seen = ago (hours (24 * 90)))
  ?(trusted = true)
  ()
  =
  let b =
    Payments_core.Beneficiary.create
      ~id:(Payments_core.Beneficiary.Id.of_string id)
      ~owner:"cust-1"
      ~name:"Test Payee"
      ~rail
      ~now:first_seen
      destination
    |> Or_error.ok_exn
  in
  { b with trusted }
;;

let btc_address = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"

let wallet_beneficiary () =
  beneficiary ~rail:(Onchain Bitcoin) ~destination:btc_address ()
;;

let draft ?(id = "tr-1") ?beneficiary:(b = beneficiary ()) amount =
  let rail : Payments_core.Rail.t =
    match b.destination with
    | Crypto { address; memo = _ } ->
      Onchain (Payments_core.Crypto_address.network address)
    | Bank_account _ -> Sepa_instant
    | Lightning _ -> Lightning
    | Internal _ -> Intraledger
  in
  Payments_core.Transfer.draft
    ~id:(Payments_core.Transfer.Id.of_string id)
    ~rail
    ~account:(Ledger.Account_id.of_string "customer:1/eur")
    ~beneficiary:b
    ~amount
    ~now:t0
    ()
  |> Or_error.ok_exn
;;

let transfer ?id ?beneficiary ?country ?wallet amount =
  Context.Subject.Transfer
    (Or_error.ok_exn
       (Context.Transfer.create ?country ?wallet (draft ?id ?beneficiary amount)))
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

let past span amount =
  { Context.Past_transfer.at = ago span
  ; amount
  ; beneficiary = Some (Payments_core.Beneficiary.Id.of_string "ben-1")
  }
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
