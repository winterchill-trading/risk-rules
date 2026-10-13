(** One threshold amount per currency, e.g. [["1000.00 EUR"; "0.05000000 BTC"]].

    A currency with no entry is treated as a limit of zero: every rule that reads limits
    fails closed on a currency the policy author forgot, and says so in its reason, rather
    than letting it through unchecked. *)

open! Core

type t [@@deriving sexp, compare, equal]

(** Fails on two entries for one currency or a negative entry. *)
val create : Money.Amount.t list -> t Or_error.t

val create_exn : Money.Amount.t list -> t
val to_list : t -> Money.Amount.t list

(** [`Configured limit] or [`Missing zero]. *)
val find
  :  t
  -> Money.Currency.t
  -> [ `Configured of Money.Amount.t | `Missing of Money.Amount.t ]

(** The limit (zero when missing) and a suffix for reasons, empty when the limit is
    configured. *)
val limit_for : t -> Money.Currency.t -> Money.Amount.t * string
