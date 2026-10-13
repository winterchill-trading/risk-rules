(** A built-in rule as data, so policies can live in sexp files.

    {v
      (Per_transfer_cap ("1000.00 EUR" "0.05000000 BTC"))
      (Velocity (max_count 5) (window 10m))
      (Severity Review (Daily_cap ("2000.00 EUR")))
    v}

    [Severity] overrides the default severity of the spec it wraps. *)

open! Core

type t =
  | Per_transfer_cap of Limits.t
  | Daily_cap of Limits.t
  | Monthly_cap of Limits.t
  | Window_cap of
      { name : string
      ; window : Time_ns.Span.t
      ; limits : Limits.t
      }
  | Velocity of
      { max_count : int
      ; window : Time_ns.Span.t
      }
  | New_beneficiary_cooldown of
      { cooldown : Time_ns.Span.t
      ; above : Limits.t
      ; exempt_trusted : bool [@sexp.bool]
      }
  | Structuring of
      { threshold : Limits.t
      ; round_unit : Limits.t
      ; margin_bps : int [@default 1_000]
      ; min_count : int
      ; window : Time_ns.Span.t
      }
  | Blocked_countries of Country.t list
  | High_risk_countries of Country.t list
  | Unverified_self_hosted_wallet of { above : Limits.t }
  | Blocked_mccs of Mcc.t list
  | Online_toggle
  | Manual_review of { reason : string }
  (** Every operation goes to review, e.g. for a tier under investigation. *)
  | Severity of Severity.t * t
[@@deriving sexp, compare, equal]

(** Range checks that sexp parsing cannot express (positive counts and windows, a margin
    within 0..10_000 basis points). *)
val validate : t -> unit Or_error.t

val to_rule : t -> Context.t Rule.t
