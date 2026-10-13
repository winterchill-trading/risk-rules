open! Core

module Wallet = struct
  type t =
    { self_hosted : bool
    ; ownership_verified : bool
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Beneficiary = struct
  type t =
    { id : string
    ; country : Country.t option
    ; first_seen : Time_ns.Alternate_sexp.t
    ; trusted : bool
    ; wallet : Wallet.t option
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Transfer = struct
  type t =
    { id : string
    ; amount : Money.Amount.Stable.V1.t
    ; rail : Payments_core.Rail.Stable.V1.t
    ; beneficiary : Beneficiary.t
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Past_transfer = struct
  type t =
    { at : Time_ns.Alternate_sexp.t
    ; amount : Money.Amount.Stable.V1.t
    ; beneficiary_id : string
    }
  [@@deriving bin_io, sexp, compare, equal]
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
  | Transfer transfer -> transfer.amount
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
    | Transfer transfer -> transfer.beneficiary.country
    | Card_auth auth -> auth.merchant_country
  in
  List.stable_dedup
    (List.filter_opt [ counterparty; t.geo.ip_country ])
    ~compare:Country.compare
;;
