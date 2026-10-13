(** Families of financial crime and control a hit belongs to, named after the usual
    transaction-monitoring typologies so audit logs and model training labels group the
    same way. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      | Limits (** product and tier limits, not suspicion *)
      | Velocity
      | Structuring (** splitting amounts to stay under reporting lines *)
      | Money_mule (** funds received and passed straight on *)
      | Account_takeover
      | App_fraud (** authorised push payment scams *)
      | Sanctions_geography
      | Travel_rule
      | Card_controls
      | Model_score
      | Strong_authentication
      | Operational (** configuration and rule errors *)
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t =
  | Limits
  | Velocity
  | Structuring
  | Money_mule
  | Account_takeover
  | App_fraud
  | Sanctions_geography
  | Travel_rule
  | Card_controls
  | Model_score
  | Strong_authentication
  | Operational
[@@deriving sexp, compare, equal, hash, enumerate, quickcheck]

(** ["money_mule"]. *)
val to_string : t -> string
