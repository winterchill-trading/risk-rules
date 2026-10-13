(** Which rules apply to which customer tier.

    {v
      ((all_tiers
        ((Blocked_countries (KP IR))
         (High_risk_countries (PA))
         Online_toggle))
       (tiers
        ((basic
          ((Per_transfer_cap ("1000.00 EUR"))
           (Daily_cap ("2000.00 EUR"))))
         (verified
          ((Per_transfer_cap ("10000.00 EUR")))))))
    v}

    A tier gets the [all_tiers] rules followed by its own. *)

open! Core

type t [@@deriving sexp, compare, equal]

(** Fails on a tier listed twice or a spec that does not validate. *)
val create
  :  all_tiers:Rule_spec.t list
  -> tiers:(Tier.t * Rule_spec.t list) list
  -> t Or_error.t

val all_tiers : t -> Rule_spec.t list
val tiers : t -> Tier.t list

(** The specs for a tier, [all_tiers] first. Fails on an unknown tier. *)
val specs_for : t -> Tier.t -> Rule_spec.t list Or_error.t

val rules_for : t -> Tier.t -> Context.t Rule.t list Or_error.t

(** Evaluates the context's tier. A tier the policy does not know is a [Block] (hit
    ["unknown_tier"]): a customer must never fall through to no rules because of a typo in
    the policy or a new tier in the product. *)
val evaluate : t -> Context.t -> Decision.t

(** Parse and validate a policy from sexp text. *)
val of_string : string -> t Or_error.t

(** [of_string] on a file's contents. *)
val load : string -> t Or_error.t
