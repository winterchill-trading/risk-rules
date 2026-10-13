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
  | Severity of Severity.t * t
[@@deriving sexp, compare, equal]

let positive_span what span =
  if Time_ns.Span.( > ) span Time_ns.Span.zero
  then Ok ()
  else
    Or_error.error_s
      [%message "rule spec: window must be positive" what (span : Time_ns.Span.t)]
;;

let positive_int what n =
  if n > 0
  then Ok ()
  else Or_error.error_s [%message "rule spec: must be positive" what (n : int)]
;;

let rec validate = function
  | Per_transfer_cap _
  | Daily_cap _
  | Monthly_cap _
  | Blocked_countries _
  | High_risk_countries _
  | Unverified_self_hosted_wallet _
  | Blocked_mccs _
  | Online_toggle
  | Manual_review _ -> Ok ()
  | Window_cap { window; name; limits = _ } ->
    if String.is_empty name
    then Or_error.error_string "rule spec: window cap needs a name"
    else positive_span "window" window
  | Velocity { max_count; window } ->
    Or_error.combine_errors_unit
      [ positive_int "max_count" max_count; positive_span "window" window ]
  | New_beneficiary_cooldown { cooldown; above = _; exempt_trusted = _ } ->
    positive_span "cooldown" cooldown
  | Structuring { margin_bps; min_count; window; threshold = _; round_unit = _ } ->
    Or_error.combine_errors_unit
      [ (if margin_bps >= 0 && margin_bps <= 10_000
         then Ok ()
         else
           Or_error.error_s
             [%message "rule spec: margin_bps outside 0..10000" (margin_bps : int)])
      ; positive_int "min_count" min_count
      ; positive_span "window" window
      ]
  | Severity (_, spec) -> validate spec
;;

let rec to_rule_with ?severity = function
  | Per_transfer_cap limits -> Rules.per_transfer_cap ?severity limits
  | Daily_cap limits -> Rules.daily_cap ?severity limits
  | Monthly_cap limits -> Rules.monthly_cap ?severity limits
  | Window_cap { name; window; limits } -> Rules.window_cap ~name ?severity ~window limits
  | Velocity { max_count; window } -> Rules.velocity ?severity ~max_count ~window ()
  | New_beneficiary_cooldown { cooldown; above; exempt_trusted } ->
    Rules.new_beneficiary_cooldown ?severity ~exempt_trusted ~cooldown ~above ()
  | Structuring { threshold; round_unit; margin_bps; min_count; window } ->
    Rules.structuring ?severity ~threshold ~round_unit ~margin_bps ~min_count ~window ()
  | Blocked_countries countries -> Rules.blocked_countries ?severity countries
  | High_risk_countries countries -> Rules.high_risk_countries ?severity countries
  | Unverified_self_hosted_wallet { above } ->
    Rules.unverified_self_hosted_wallet ?severity ~above ()
  | Blocked_mccs mccs -> Rules.blocked_mccs ?severity mccs
  | Online_toggle -> Rules.online_toggle ?severity ()
  | Manual_review { reason } ->
    Rule.always
      ~name:"manual_review"
      ~severity:(Option.value severity ~default:Severity.Review)
      ~reason
  (* The outermost override wins: [(Severity Block (Severity Review x))] is [Block]. *)
  | Severity (outer, spec) ->
    to_rule_with ~severity:(Option.value severity ~default:outer) spec
;;

let to_rule spec = to_rule_with spec
