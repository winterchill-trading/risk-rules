(** Model features, defined once.

    Rules, the scoring models and the offline training pipeline all read these values, so
    a feature means the same thing in production and in training. The training side reads
    the JSON export ({!to_json}) or the numeric vector ({!to_floats}) and checks
    {!schema_version}; any change to a field's meaning or a new field bumps the version
    and adds a [Stable] module.

    Conventions: amounts are in major units of the subject's currency ([12.34] for "12.34
    EUR") as floats, which is fine for models and never used for money movement; sums only
    include history in that currency; "24h" and "1h" windows are rolling and end at
    [Context.now], and the current operation is not part of any history count. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      { schema_version : int (** always 1 for this version *)
      ; is_card : bool
      ; rail : string (** ["card"] or the payments-core rail, e.g. ["sepa_instant"] *)
      ; card_channel : string option (** ["Online"], ["In_person"], ["Atm"] *)
      ; currency : string
      ; amount : float
      ; amount_is_round : bool (** a positive multiple of 100 major units *)
      ; balance : float option (** available balance in the currency *)
      ; amount_to_balance : float option (** [amount / balance] when balance > 0 *)
      ; beneficiary_age_hours : float option (** since the beneficiary was first used *)
      ; beneficiary_trusted : bool option
      ; counterparty_country_is_residence : bool option
      ; self_hosted_unverified : bool
      (** crypto to a wallet the customer has not proven *)
      ; mcc : int option
      ; out_count_1h : int
      ; out_count_24h : int
      ; out_sum_24h : float
      ; out_sum_30d : float
      ; out_distinct_beneficiaries_24h : int
      ; in_count_24h : int
      ; in_sum_24h : float
      ; pass_through_ratio_24h : float option
      (** [(out_sum_24h + amount) / in_sum_24h] when money came in *)
      ; new_device : bool
      ; ip_country_is_residence : bool option
      ; hours_since_credentials_change : float option
      ; account_age_days : float option
      ; hour_of_day_utc : int
      ; log1p_amount : float (** [log (1 + amount)] *)
      ; is_weekend : bool (** Saturday or Sunday, UTC *)
      ; out_count_7d : int
      ; out_sum_1h : float
      ; out_sum_7d : float
      ; amount_over_mean_30d : float option
      (** amount / mean outgoing amount in the currency over 30 days *)
      ; in_distinct_senders_24h : int
      ; minutes_since_last_inbound : float option
      ; failed_sca_24h : int
      ; payee_check : string option
      (** verification of payee: ["Match"], ["Close_match"], ["No_match"],
          ["Not_possible"] *)
      ; card_auths_10m : int (** earlier authorisations on the card, 10 minutes *)
      ; card_declines_10m : int
      }
    [@@deriving bin_io, sexp, compare, equal, yojson]
  end
end

type t = Stable.V1.t [@@deriving sexp, compare, equal, yojson]

val schema_version : int
val of_context : Context.t -> t

(** Field names in export order with a one-line meaning, for the training pipeline's
    schema check. *)
val schema : (string * string) list

(** Numeric vector in {!schema} order without the categorical string fields ([rail],
    [card_channel], [currency], [payee_check]): booleans are 0/1, a missing option is
    [Float.nan]. *)
val to_floats : t -> (string * float) list

(** The names {!to_floats} returns, in order. *)
val numeric_names : string list

val to_json : t -> string
val of_json : string -> t Or_error.t
