(** What a decision means for strong customer authentication, in payments-core terms: the
    caller either starts a challenge ([Transfer.require_sca]) or records the exemption
    ([Transfer.exempt]), which keeps the liability trail on the transfer. *)

open! Core

type t =
  | Required of { reasons : string list } (** the [SCA_REQUIRED] hits' reasons *)
  | Exempt of Payments_core.Sca.Exemption.t
  | Not_assessed (** no SCA rule in the policy looked at this operation *)
[@@deriving sexp_of, compare, equal]

(** A [Challenge] or worse [SCA_REQUIRED] hit wins over any exemption. *)
val of_decision : Decision.t -> t
