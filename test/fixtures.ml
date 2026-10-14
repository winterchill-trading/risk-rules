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

let beneficiary_default () = beneficiary ()
let btc_address = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"

let wallet_beneficiary ?trusted () =
  beneficiary ?trusted ~rail:(Onchain Bitcoin) ~destination:btc_address ()
;;

(* The customer's own IBAN, needed for the SEPA debtor party. *)
let debtor_iban =
  let bban = "100100100123456789" in
  Payments_core.Iban.of_string_exn
    ("DE" ^ Payments_core.Iban.check_digits ~country:"DE" ~bban ^ bban)
;;

let sepa_details ~creditor_iban =
  let party name iban : Payments_core.Iso20022.Party.t =
    { name; iban; bic = None; address = None }
  in
  Payments_core.Transfer.Details.Sepa
    (Payments_core.Sepa.Details.create
       ~payment_id:
         (Payments_core.Iso20022.Payment_id.create ~end_to_end_id:"E2E-1" ()
          |> Or_error.ok_exn)
       ~debtor:(party "Customer One" debtor_iban)
       ~creditor:(party "Test Payee" creditor_iban)
       ~remittance:
         (Payments_core.Iso20022.Remittance.unstructured "test" |> Or_error.ok_exn)
       ())
;;

let travel_rule ~address ~wallet : Payments_core.Transfer.Details.t =
  let person name account : Payments_core.Travel_rule.Person.t =
    { name; account; identification = Some (Customer_number "cust-1"); lei = None }
  in
  Onchain
    { travel_rule =
        Some
          { originator = person "Customer One" "cust-1"
          ; beneficiary = person "Test Payee" address
          ; counterparty_wallet = wallet
          }
    ; tx_hash = None
    ; block_hash = None
    ; confirmations = 0
    ; finalized = false
    }
;;

(* [eur_value] is fixed and below the 1000 EUR self-hosted threshold so payments-core
   accepts unverified wallets; the risk rule under test uses its own, lower thresholds. *)
let draft
  ?(id = "tr-1")
  ?beneficiary
  ?(wallet =
    Payments_core.Travel_rule.Counterparty_wallet.Hosted
      { provider_name = "Exchange"; provider_lei = None })
  amount
  =
  (* Default payee by currency: a SEPA account for EUR, a Bitcoin address for BTC (SEPA
     only carries EUR). *)
  let b =
    match beneficiary with
    | Some b -> b
    | None ->
      if Money.Currency.equal (Money.Amount.currency amount) Money.Currency.btc
      then wallet_beneficiary ()
      else beneficiary_default ()
  in
  let rail : Payments_core.Rail.t =
    match b.destination with
    | Crypto { address; memo = _ } ->
      Onchain (Payments_core.Crypto_address.network address)
    | Bank_account _ -> Sepa_instant
    | Lightning _ -> Lightning
    | Internal _ -> Intraledger
    | Uk_account _ -> Faster_payments
    | Us_account _ -> Ach { sec = Ppd; same_day = false }
  in
  let details =
    match b.destination with
    | Bank_account { iban; bic = _ } -> Some (sepa_details ~creditor_iban:iban)
    | Crypto { address; memo = _ } ->
      Some (travel_rule ~address:(Payments_core.Crypto_address.address address) ~wallet)
    | Lightning _ | Internal _ | Uk_account _ | Us_account _ -> None
  in
  Payments_core.Transfer.draft
    ?details
    ~eur_value:(eur "100.00")
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
       (Context.Transfer.create ?country (draft ?id ?beneficiary ?wallet amount)))
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
  ; sender = None
  }
;;

let context
  ?(tier = "basic")
  ?(history = [])
  ?(incoming = [])
  ?(card_history = [])
  ?(geo = Context.Geo.unknown)
  ?(session = Context.Session.unknown)
  ?(balances = [ eur "10000.00" ])
  subject
  =
  { Context.customer = "cust-1"
  ; tier = Tier.of_string tier
  ; now = t0
  ; balances
  ; subject
  ; history
  ; incoming
  ; card_history
  ; geo
  ; session
  }
;;

(* Prints the rule's verdict: "-" when it stays silent. *)
let check rule ctx =
  match Rule.check rule ctx with
  | None -> print_endline "-"
  | Some hit -> printf "%s: %s\n" (Severity.to_string hit.severity) hit.reason
;;
