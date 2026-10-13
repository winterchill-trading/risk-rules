(** Built-in rules over {!Context}.

    Each function returns one rule with a default name (shown in hits and used by
    operators to filter) and a default severity, both overridable. Amount thresholds are
    {!Limits}: a currency the limits do not list counts as a limit of zero, so these rules
    fail closed on a forgotten currency.

    Transfer rules ignore card authorisations and the other way round. *)

open! Core

(** {2 Amount caps on transfers} *)

(** The transfer alone exceeds the limit. Default [Block]. *)
val per_transfer_cap
  :  ?name:string
  -> ?severity:Severity.t
  -> Limits.t
  -> Context.t Rule.t

(** The transfer plus the customer's transfers in the same currency during the rolling
    [window] exceed the limit. Default [Block]. *)
val window_cap
  :  name:string
  -> ?severity:Severity.t
  -> window:Time_ns.Span.t
  -> Limits.t
  -> Context.t Rule.t

(** [window_cap] over a rolling 24 hours, named ["daily_cap"]. *)
val daily_cap : ?severity:Severity.t -> Limits.t -> Context.t Rule.t

(** [window_cap] over a rolling 30 days, named ["monthly_cap"]. *)
val monthly_cap : ?severity:Severity.t -> Limits.t -> Context.t Rule.t

(** {2 Behaviour} *)

(** More than [max_count] transfers (this one included) within [window], in any currency.
    Default [Review]. *)
val velocity
  :  ?name:string
  -> ?severity:Severity.t
  -> max_count:int
  -> window:Time_ns.Span.t
  -> unit
  -> Context.t Rule.t

(** A transfer above [above] to a beneficiary first used less than [cooldown] ago. Trusted
    beneficiaries are not exempt unless [exempt_trusted]: an account takeover can confirm
    a new beneficiary too. Default [Block]. *)
val new_beneficiary_cooldown
  :  ?name:string
  -> ?severity:Severity.t
  -> ?exempt_trusted:bool
  -> cooldown:Time_ns.Span.t
  -> above:Limits.t
  -> unit
  -> Context.t Rule.t

(** Round-amount structuring heuristic. A transfer is suspicious when its amount is a
    positive multiple of [round_unit] or lies within [margin_bps] below [threshold] (just
    under a reporting line). Triggers when this transfer is suspicious and at least
    [min_count] suspicious transfers (this one included) fall within [window]. Default
    [Review]. *)
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

(** {2 Geography} *)

(** Any country of {!Context.countries} is listed. Default [Block], named
    ["blocked_country"]. *)
val blocked_countries
  :  ?name:string
  -> ?severity:Severity.t
  -> Country.t list
  -> Context.t Rule.t

(** Same check with default [Review], named ["high_risk_country"]. *)
val high_risk_countries
  :  ?name:string
  -> ?severity:Severity.t
  -> Country.t list
  -> Context.t Rule.t

(** {2 Crypto} *)

(** A withdrawal above [above] to a self-hosted wallet whose ownership the customer has
    not proven. This is the travel-rule hook: the reason asks for originator and
    beneficiary information before release. Default [Review]. *)
val unverified_self_hosted_wallet
  :  ?name:string
  -> ?severity:Severity.t
  -> above:Limits.t
  -> unit
  -> Context.t Rule.t

(** {2 Cards} *)

(** The merchant category is listed. Default [Block]. *)
val blocked_mccs : ?name:string -> ?severity:Severity.t -> Mcc.t list -> Context.t Rule.t

(** An online (card not present) authorisation while the cardholder has online payments
    switched off. Default [Block]. *)
val online_toggle : ?name:string -> ?severity:Severity.t -> unit -> Context.t Rule.t
