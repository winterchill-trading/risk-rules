(** Stable reason codes carried by every hit.

    A code has three audiences: the audit log (the code and the hit's detailed reason),
    operators (the description) and the customer (a decline message). Customer messages
    are deliberately generic for suspicion typologies (mule, structuring, account
    takeover, scores): telling a customer that a payment looks like money laundering can
    amount to tipping off, so they only say the payment needs a check.

    The text form (["LIMIT_DAILY"], ["CUSTOM_MY_RULE"]) is the stable identifier; sexp
    uses it too. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      | Limit_per_transfer
      | Limit_daily
      | Limit_monthly
      | Limit_window
      | Velocity_out
      | New_beneficiary_cooldown
      | Structuring
      | Geo_blocked
      | Geo_high_risk
      | Travel_rule_self_hosted
      | Card_mcc_blocked
      | Card_online_disabled
      | Manual_review
      | Mule_pass_through
      | Account_takeover_signals
      | App_new_beneficiary_balance
      | Score_high
      | Score_unavailable
      | Sca_required
      | Rule_error
      | Unknown_tier
      | Custom of string (** codes of rules written outside this library *)
    [@@deriving bin_io, compare, equal, hash]

    include Sexpable.S with type t := t
  end
end

type t = Stable.V1.t =
  | Limit_per_transfer
  | Limit_daily
  | Limit_monthly
  | Limit_window
  | Velocity_out
  | New_beneficiary_cooldown
  | Structuring
  | Geo_blocked
  | Geo_high_risk
  | Travel_rule_self_hosted
  | Card_mcc_blocked
  | Card_online_disabled
  | Manual_review
  | Mule_pass_through
  | Account_takeover_signals
  | App_new_beneficiary_balance
  | Score_high
  | Score_unavailable
  | Sca_required
  | Rule_error
  | Unknown_tier
  | Custom of string
[@@deriving compare, equal, hash, quickcheck]

include Sexpable.S with type t := t
include Stringable.S with type t := t

(** Every code except [Custom]. *)
val builtin : t list

val typology : t -> Typology.t

(** One line for operators: what the code means. *)
val description : t -> string

(** Text safe to show the customer when this code decides the outcome. *)
val customer_message : t -> string
