open! Core

module Wallet = struct
  type t =
    { self_hosted : bool
    ; ownership_verified : bool
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Transfer = struct
  type t =
    { draft : Payments_core.Transfer.Stable.V1.t
    ; beneficiary : Payments_core.Beneficiary.Stable.V1.t
    ; beneficiary_country : Country.t option
    ; wallet : Wallet.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  let default_country (beneficiary : Payments_core.Beneficiary.t) =
    match beneficiary.destination with
    | Bank_account { iban; bic = _ } ->
      Country.of_string_or_error (Payments_core.Iban.country iban) |> Result.ok
    | Crypto _ | Lightning _ | Internal _ -> None
  ;;

  let create ?country ?wallet (draft : Payments_core.Transfer.t) =
    match draft.direction, draft.counterparty with
    | Out, Beneficiary beneficiary ->
      let beneficiary_country =
        match country with
        | Some _ -> country
        | None -> default_country beneficiary
      in
      Ok { draft; beneficiary; beneficiary_country; wallet }
    | In, _ | Out, External _ ->
      Or_error.error_s
        [%message
          "context: expected an outgoing transfer to a beneficiary"
            ~transfer:(draft.id : Payments_core.Transfer.Id.t)]
  ;;

  let amount t = t.draft.amount
end

module Past_transfer = struct
  type t =
    { at : Time_ns.Alternate_sexp.t
    ; amount : Money.Amount.Stable.V1.t
    ; beneficiary : Payments_core.Beneficiary.Id.Stable.V1.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  let of_transfer (transfer : Payments_core.Transfer.t) =
    (* Transfers still waiting for strong authentication count: otherwise a customer could
       queue many unconfirmed transfers that each pass the cap alone and confirm them
       together. *)
    let counts =
      match transfer.status with
      | Awaiting_sca | Submitted | Pending | Settled -> true
      | Draft | Failed _ | Returned | Cancelled -> false
    in
    match transfer.direction, counts, List.last transfer.history with
    | Out, true, Some (_, at) ->
      let beneficiary =
        match transfer.counterparty with
        | Beneficiary b -> Some b.id
        | External _ -> None
      in
      Some { at; amount = transfer.amount; beneficiary }
    | (In | Out), _, _ -> None
  ;;
end

module Card_auth = struct
  module Channel = struct
    type t =
      | In_person
      | Online
      | Atm
    [@@deriving bin_io, sexp, compare, equal, enumerate]
  end

  type t =
    { id : string
    ; amount : Money.Amount.Stable.V1.t
    ; mcc : Mcc.Stable.V1.t
    ; merchant_country : Country.t option
    ; channel : Channel.t
    ; online_enabled : bool
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Geo = struct
  type t =
    { ip_country : Country.t option
    ; residence : Country.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  let unknown = { ip_country = None; residence = None }
end

module Subject = struct
  type t =
    | Transfer of Transfer.t
    | Card_auth of Card_auth.t
  [@@deriving bin_io, sexp, compare, equal]
end

type t =
  { customer : string
  ; tier : Tier.Stable.V1.t
  ; now : Time_ns.Alternate_sexp.t
  ; balances : Money.Amount.Stable.V1.t list
  ; subject : Subject.t
  ; history : Past_transfer.t list
  ; geo : Geo.t
  }
[@@deriving bin_io, sexp, compare, equal]

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end

let amount t =
  match t.subject with
  | Transfer transfer -> Transfer.amount transfer
  | Card_auth auth -> auth.amount
;;

let transfer t =
  match t.subject with
  | Transfer transfer -> Some transfer
  | Card_auth _ -> None
;;

let card_auth t =
  match t.subject with
  | Card_auth auth -> Some auth
  | Transfer _ -> None
;;

let balance t currency =
  List.find t.balances ~f:(fun amount ->
    Money.Currency.equal (Money.Amount.currency amount) currency)
;;

let history_within t ~window =
  let since = Time_ns.sub t.now window in
  List.filter t.history ~f:(fun (past : Past_transfer.t) ->
    Time_ns.( > ) past.at since && Time_ns.( <= ) past.at t.now)
;;

let countries t =
  let counterparty =
    match t.subject with
    | Transfer transfer -> transfer.beneficiary_country
    | Card_auth auth -> auth.merchant_country
  in
  List.stable_dedup
    (List.filter_opt [ counterparty; t.geo.ip_country ])
    ~compare:Country.compare
;;
