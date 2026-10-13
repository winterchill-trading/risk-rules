(** Everything a rule may look at, gathered by the caller before evaluation.

    Rules are pure functions of this value: the caller reads balances, history and
    beneficiary facts from its stores and fixes [now], so an evaluation can be replayed
    from a logged context and gives the same decision. The types are bin_io so a context
    can be journaled next to its decision for audit. *)

open! Core

module Wallet : sig
  (** Facts about a crypto destination address. *)
  type t =
    { self_hosted : bool (** not held at a regulated custodian *)
    ; ownership_verified : bool
    (** the customer proved control (signed message, satoshi test) *)
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Transfer : sig
  (** The outgoing transfer being decided, with the facts about its beneficiary that
      payments-core does not hold. Built with {!create}, which keeps [beneficiary] equal
      to the draft's counterparty. *)
  type t = private
    { draft : Payments_core.Transfer.Stable.V1.t
    ; beneficiary : Payments_core.Beneficiary.Stable.V1.t
    ; beneficiary_country : Country.t option
    (** bank or wallet provider country, when known *)
    ; wallet : Wallet.t option (** [Some] for crypto destinations *)
    }
  [@@deriving bin_io, sexp, compare, equal]

  (** Fails unless the draft is outgoing to a beneficiary. [country] defaults to the
      IBAN's country for bank accounts and is [None] otherwise. *)
  val create
    :  ?country:Country.t
    -> ?wallet:Wallet.t
    -> Payments_core.Transfer.t
    -> t Or_error.t

  (** What the beneficiary receives, fee excluded: limits are about money sent, and a fee
      change should not move a customer across a cap. *)
  val amount : t -> Money.Amount.t
end

module Past_transfer : sig
  (** An earlier outgoing transfer of the same customer that counts towards limits:
      accepted, pending or settled, but not failed or rejected. *)
  type t =
    { at : Time_ns.Alternate_sexp.t
    ; amount : Money.Amount.Stable.V1.t
    ; beneficiary : Payments_core.Beneficiary.Id.Stable.V1.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  (** Summarises a payments-core transfer: [None] for incoming transfers and for drafts,
      failed, cancelled and returned ones, which moved no money. [at] is when it was
      created (its oldest history entry). *)
  val of_transfer : Payments_core.Transfer.t -> t option

  (** Summarises an incoming transfer that reached the account (pending or settled);
      [None] otherwise. [beneficiary] is [None]. *)
  val of_incoming : Payments_core.Transfer.t -> t option
end

module Card_auth : sig
  module Channel : sig
    type t =
      | In_person
      | Online (** card not present: e-commerce, mail and phone order *)
      | Atm
    [@@deriving bin_io, sexp, compare, equal, enumerate]
  end

  (** A card authorisation request. *)
  type t =
    { id : string
    ; amount : Money.Amount.Stable.V1.t
    ; mcc : Mcc.Stable.V1.t
    ; merchant_country : Country.t option
    ; channel : Channel.t
    ; online_enabled : bool (** the cardholder's online payments toggle *)
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Geo : sig
  type t =
    { ip_country : Country.t option (** where the request came from *)
    ; residence : Country.t option (** the customer's country of residence *)
    }
  [@@deriving bin_io, sexp, compare, equal]

  val unknown : t
end

module Session : sig
  (** Signals about the channel the request came through, used for account takeover
      detection. *)
  type t =
    { new_device : bool (** first request from this device or browser *)
    ; credentials_changed_at : Time_ns.Alternate_sexp.t option
    (** last password, phone or e-mail change *)
    ; account_opened_at : Time_ns.Alternate_sexp.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  (** No signals: a known device, no recent changes, account age unknown. *)
  val unknown : t
end

module Subject : sig
  type t =
    | Transfer of Transfer.t
    | Card_auth of Card_auth.t
  [@@deriving bin_io, sexp, compare, equal]
end

type t =
  { customer : string
  ; tier : Tier.Stable.V1.t
  ; now : Time_ns.Alternate_sexp.t
  ; balances : Money.Amount.Stable.V1.t list (** available balance per currency *)
  ; subject : Subject.t
  ; history : Past_transfer.t list (** outgoing, any order; rules filter by time *)
  ; incoming : Past_transfer.t list (** credits received, any order *)
  ; geo : Geo.t
  ; session : Session.t
  }
[@@deriving bin_io, sexp, compare, equal]

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end

(** The amount being moved or authorised. *)
val amount : t -> Money.Amount.t

val transfer : t -> Transfer.t option
val card_auth : t -> Card_auth.t option

(** Available balance in a currency, if the customer holds one. *)
val balance : t -> Money.Currency.t -> Money.Amount.t option

(** Incoming transfers with [now - window < at <= now]. *)
val incoming_within : t -> window:Time_ns.Span.t -> Past_transfer.t list

(** Past transfers with [now - window < at <= now]. Entries dated after [now] (clock skew
    between services) are ignored rather than counted. *)
val history_within : t -> window:Time_ns.Span.t -> Past_transfer.t list

(** Countries involved, without duplicates: beneficiary or merchant country first, then
    the request's IP country. *)
val countries : t -> Country.t list
