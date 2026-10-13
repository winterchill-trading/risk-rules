(** A built-in rule as data, so policies can live in sexp files.

    {v
      (Per_transfer_cap ("1000.00 EUR" "0.05000000 BTC"))
      (Velocity (max_count 5) (window 10m))
      (Severity Review (Daily_cap ("2000.00 EUR")))
      (Score (model fraud-v3) (thresholds ((challenge_at 0.5) (review_at 0.8) (block_at 0.97))))
      (Sca_tra (scheme Credit_transfer) (observed_fraud_rate_ppm 40))
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
  | Mule_pass_through of
      { window : Time_ns.Span.t
      ; min_incoming : Limits.t
      ; ratio_bps : int [@default 8_000]
      }
  | Account_takeover of
      { recent : Time_ns.Span.t
      ; min_signals : int [@default 2]
      }
  | App_fraud of
      { new_within : Time_ns.Span.t
      ; balance_share_bps : int [@default 8_000]
      }
  | Score of
      { model : string (** looked up by {!Model.name} *)
      ; thresholds : Rules.Thresholds.t
      }
  | Sca_tra of
      { scheme : Rules.Tra.scheme
      ; observed_fraud_rate_ppm : int
      ; trusted_beneficiaries_exempt : bool [@default true]
      ; recent : Time_ns.Span.t [@default Time_ns.Span.day]
      ; model : string option [@sexp.option]
      ; max_score : float [@default 1.]
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

(** [models] are the scoring models available to [Score] and [Sca_tra] specs, by
    {!Model.name}. A spec naming a model that is not loaded becomes a [Review] rule with
    code [Score_unavailable]: payments are held rather than let through unscored or
    refused outright. *)
val to_rule : ?models:Model.t list -> t -> Context.t Rule.t

(** Model names the spec refers to. *)
val models : t -> string list
