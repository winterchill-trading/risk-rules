(** Built-in rules over {!Context}.

    Each function returns one rule with a default name (shown in hits and used by
    operators to filter), a fixed {!Reason_code} and a default severity that can be
    overridden. Every hit carries evidence: the values the rule compared, for the audit
    log.

    Amount thresholds are {!Limits}: a currency the limits do not list counts as a limit
    of zero, so cap rules fail closed on a forgotten currency. Transfer rules ignore card
    authorisations and the other way round. *)

open! Core

(** {2 Limits} *)

(** The transfer alone exceeds the limit. [Limit_per_transfer], default [Block]. *)
val per_transfer_cap
  :  ?name:string
  -> ?severity:Severity.t
  -> Limits.t
  -> Context.t Rule.t

(** The transfer plus the customer's transfers in the same currency during the rolling
    [window] exceed the limit. [Limit_window], default [Block]. *)
val window_cap
  :  name:string
  -> ?severity:Severity.t
  -> window:Time_ns.Span.t
  -> Limits.t
  -> Context.t Rule.t

(** Rolling 24 hours, named ["daily_cap"], code [Limit_daily]. *)
val daily_cap : ?severity:Severity.t -> Limits.t -> Context.t Rule.t

(** Rolling 30 days, named ["monthly_cap"], code [Limit_monthly]. *)
val monthly_cap : ?severity:Severity.t -> Limits.t -> Context.t Rule.t

(** {2 Typologies} *)

(** More than [max_count] transfers (this one included) within [window], in any currency.
    [Velocity_out], default [Review]. *)
val velocity
  :  ?name:string
  -> ?severity:Severity.t
  -> max_count:int
  -> window:Time_ns.Span.t
  -> unit
  -> Context.t Rule.t

(** A transfer above [above] to a beneficiary first used less than [cooldown] ago. Trusted
    beneficiaries are not exempt unless [exempt_trusted]: an account takeover can confirm
    a new beneficiary too. [New_beneficiary_cooldown], default [Block]. *)
val new_beneficiary_cooldown
  :  ?name:string
  -> ?severity:Severity.t
  -> ?exempt_trusted:bool
  -> cooldown:Time_ns.Span.t
  -> above:Limits.t
  -> unit
  -> Context.t Rule.t

(** Structuring. A transfer is suspicious when its amount is a positive multiple of
    [round_unit] or lies within [margin_bps] below [threshold] (just under a reporting
    line). Triggers when this transfer is suspicious and at least [min_count] suspicious
    transfers (this one included) fall within [window]. Unlike the caps, a currency
    missing from [threshold] or [round_unit] switches that half off. [Structuring],
    default [Review]. *)
val structuring
  :  ?name:string
  -> ?severity:Severity.t
  -> threshold:Limits.t
  -> ?margin_bps:int
  -> round_unit:Limits.t
  -> min_count:int
  -> window:Time_ns.Span.t
  -> unit
  -> Context.t Rule.t

(** Money mule pass-through: at least [min_incoming] arrived in the transfer's currency
    within [window], and the outgoing total in that window including this transfer reaches
    [ratio_bps] of it. [Mule_pass_through], default [Review]. *)
val mule_pass_through
  :  ?name:string
  -> ?severity:Severity.t
  -> window:Time_ns.Span.t
  -> min_incoming:Limits.t
  -> ?ratio_bps:int
  -> unit
  -> Context.t Rule.t

(** Money mule fan-in: at least [min_senders] distinct payers within [window] into an
    account younger than [max_account_age] (unknown opening dates do not count as young).
    [Mule_fan_in], default [Review]. Evaluated on the customer's outgoing transfers, which
    is when the money can still be stopped. *)
val mule_fan_in
  :  ?name:string
  -> ?severity:Severity.t
  -> min_senders:int
  -> window:Time_ns.Span.t
  -> max_account_age:Time_ns.Span.t
  -> unit
  -> Context.t Rule.t

(** A transfer above [above] from an account opened less than [max_age] ago.
    [New_account_payout], default [Review]. *)
val new_account_payout
  :  ?name:string
  -> ?severity:Severity.t
  -> max_age:Time_ns.Span.t
  -> above:Limits.t
  -> unit
  -> Context.t Rule.t

(** Account takeover signals, counted on transfers and online card payments: a new device,
    a request from outside the residence country, credentials changed within [recent], and
    (transfers) a beneficiary first used within [recent]. Triggers at [min_signals] or
    more. [Account_takeover_signals], default [Review]. *)
val account_takeover
  :  ?name:string
  -> ?severity:Severity.t
  -> ?min_signals:int
  -> ?balance_share_bps:int
  -> recent:Time_ns.Span.t
  -> unit
  -> Context.t Rule.t

(** Authorised push payment fraud: a transfer to a beneficiary first used less than
    [new_within] ago that takes at least [balance_share_bps] of the available balance in
    its currency ("move everything to a safe account"). [App_new_beneficiary_balance],
    default [Review]. *)
val app_fraud
  :  ?name:string
  -> ?severity:Severity.t
  -> new_within:Time_ns.Span.t
  -> ?balance_share_bps:int
  -> unit
  -> Context.t Rule.t

(** A transfer to a beneficiary first used less than [new_within] ago for more than
    [multiple] times the customer's mean outgoing amount in that currency over 30 days.
    Needs at least one earlier transfer. [App_first_large_payment], default [Review]. *)
val app_first_large_payment
  :  ?name:string
  -> ?severity:Severity.t
  -> new_within:Time_ns.Span.t
  -> ?multiple:int
  -> unit
  -> Context.t Rule.t

(** The beneficiary's verification-of-payee result is [No_match] or [Close_match].
    [Vop_not_matched], default [Review]; the customer message is a scam warning. *)
val vop_not_matched : ?name:string -> ?severity:Severity.t -> unit -> Context.t Rule.t

(** {2 Geography} *)

(** Any country of {!Context.countries} is listed. [Geo_blocked], default [Block], named
    ["blocked_country"]. *)
val blocked_countries
  :  ?name:string
  -> ?severity:Severity.t
  -> Country.t list
  -> Context.t Rule.t

(** Same check, [Geo_high_risk], default [Review], named ["high_risk_country"]. *)
val high_risk_countries
  :  ?name:string
  -> ?severity:Severity.t
  -> Country.t list
  -> Context.t Rule.t

(** {2 Crypto} *)

(** A withdrawal above [above] to a self-hosted wallet whose ownership the customer has
    not proven. The travel-rule hook: hold until originator and beneficiary information or
    proof of ownership is collected. [Travel_rule_self_hosted], default [Review]. *)
val unverified_self_hosted_wallet
  :  ?name:string
  -> ?severity:Severity.t
  -> above:Limits.t
  -> unit
  -> Context.t Rule.t

(** {2 Cards} *)

(** [Card_mcc_blocked], default [Block]. *)
val blocked_mccs : ?name:string -> ?severity:Severity.t -> Mcc.t list -> Context.t Rule.t

(** An online authorisation while the cardholder has online payments switched off.
    [Card_online_disabled], default [Block]. *)
val online_toggle : ?name:string -> ?severity:Severity.t -> unit -> Context.t Rule.t

(** Card testing: at least [count] earlier authorisations below [small] within [window],
    or at least [max_declines] declines in it. [Card_testing], default [Block]. *)
val card_testing
  :  ?name:string
  -> ?severity:Severity.t
  -> small:Limits.t
  -> count:int
  -> ?max_declines:int
  -> window:Time_ns.Span.t
  -> unit
  -> Context.t Rule.t

(** {2 Model scores} *)

module Thresholds : sig
  (** Scores at or above a threshold get its severity; the highest reached wins. Absent
      thresholds are skipped. *)
  type t =
    { challenge_at : float option
    ; review_at : float option
    ; block_at : float option
    }
  [@@deriving sexp, compare, equal]

  (** Each in [0, 1] and [challenge_at <= review_at <= block_at] where present. *)
  val validate : t -> unit Or_error.t
end

(** Scores {!Features.of_context} with the model. [Score_high]; the evidence lists the
    model name, version, score and its reason codes. *)
val model_score : ?name:string -> Model.t -> Thresholds.t -> Context.t Rule.t

(** {2 Strong customer authentication} *)

module Tra : sig
  (** PSD2 transaction risk analysis exemption (RTS article 18). *)

  type scheme =
    | Credit_transfer (** remote electronic credit transfers *)
    | Card_not_present (** remote card-based payments *)
  [@@deriving sexp, compare, equal, enumerate]

  (** Reference fraud rates by exemption threshold value (RTS annex), in parts per
      million: credit transfers 150 ppm up to 100 EUR, 100 ppm up to 250 EUR, 50 ppm up to
      500 EUR; card not present 1300, 600 and 100 ppm for the same values. *)
  val reference_bands : scheme -> (Money.Amount.t * int) list

  (** The highest exemption threshold the observed fraud rate allows, if any. *)
  val threshold : scheme -> observed_fraud_rate_ppm:int -> Money.Amount.t option
end

(** Requires strong authentication ([Challenge], code [Sca_required]) on a remote payment
    unless an exemption applies: the beneficiary is trusted (RTS article 13, when
    [trusted_beneficiaries_exempt]), or the payment is in EUR, within {!Tra.threshold} for
    the observed fraud rate, shows no account takeover signal (as {!account_takeover}
    counts them with [recent]) and, when a model is given, scores below [max_score].
    In-person and ATM card payments are not remote; the rule ignores them (the card's own
    authentication applies). *)
val sca_tra
  :  ?name:string
  -> ?severity:Severity.t
  -> scheme:Tra.scheme
  -> observed_fraud_rate_ppm:int
  -> ?trusted_beneficiaries_exempt:bool
  -> ?recent:Time_ns.Span.t
  -> ?model:Model.t * float
  -> unit
  -> Context.t Rule.t
