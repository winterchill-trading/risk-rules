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
      ; balance_share_bps : int option [@sexp.option]
      }
  | App_fraud of
      { new_within : Time_ns.Span.t
      ; balance_share_bps : int [@default 8_000]
      }
  | Mule_fan_in of
      { min_senders : int
      ; window : Time_ns.Span.t
      ; max_account_age : Time_ns.Span.t
      }
  | New_account_payout of
      { max_age : Time_ns.Span.t
      ; above : Limits.t
      }
  | App_first_large_payment of
      { new_within : Time_ns.Span.t
      ; multiple : int [@default 5]
      }
  | Vop_not_matched
  | Card_testing of
      { small : Limits.t
      ; count : int
      ; max_declines : int [@default 3]
      ; window : Time_ns.Span.t
      }
  | Score of
      { model : string
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
  | Severity of Severity.t * t
  | Shadow of t
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
  | Mule_pass_through { window; ratio_bps; min_incoming = _ } ->
    Or_error.combine_errors_unit
      [ positive_span "window" window; positive_int "ratio_bps" ratio_bps ]
  | Account_takeover { recent; min_signals; balance_share_bps = _ } ->
    Or_error.combine_errors_unit
      [ positive_span "recent" recent; positive_int "min_signals" min_signals ]
  | App_fraud { new_within; balance_share_bps } ->
    Or_error.combine_errors_unit
      [ positive_span "new_within" new_within
      ; positive_int "balance_share_bps" balance_share_bps
      ]
  | Mule_fan_in { min_senders; window; max_account_age } ->
    Or_error.combine_errors_unit
      [ positive_int "min_senders" min_senders
      ; positive_span "window" window
      ; positive_span "max_account_age" max_account_age
      ]
  | New_account_payout { max_age; above = _ } -> positive_span "max_age" max_age
  | App_first_large_payment { new_within; multiple } ->
    Or_error.combine_errors_unit
      [ positive_span "new_within" new_within; positive_int "multiple" multiple ]
  | Vop_not_matched -> Ok ()
  | Card_testing { count; max_declines; window; small = _ } ->
    Or_error.combine_errors_unit
      [ positive_int "count" count
      ; positive_int "max_declines" max_declines
      ; positive_span "window" window
      ]
  | Score { thresholds; model = _ } -> Rules.Thresholds.validate thresholds
  | Sca_tra
      { observed_fraud_rate_ppm
      ; recent
      ; max_score
      ; scheme = _
      ; trusted_beneficiaries_exempt = _
      ; model = _
      } ->
    Or_error.combine_errors_unit
      [ (if observed_fraud_rate_ppm >= 0
         then Ok ()
         else Or_error.error_string "rule spec: negative fraud rate")
      ; positive_span "recent" recent
      ; (if Float.(max_score >= 0. && max_score <= 1.)
         then Ok ()
         else Or_error.error_string "rule spec: max_score outside [0, 1]")
      ]
  | Severity (_, spec) | Shadow spec -> validate spec
;;

let rec models = function
  | Score { model; _ } -> [ model ]
  | Sca_tra { model; _ } -> Option.to_list model
  | Severity (_, spec) | Shadow spec -> models spec
  | _ -> []
;;

let unavailable ~name model =
  Rule.always
    ~name
    ~severity:Review
    ~code:Score_unavailable
    ~reason:(sprintf "model %s is not loaded" model)
;;

let find_model models name =
  List.find models ~f:(fun m -> String.equal (Model.name m) name)
;;

let rec to_rule_with ~models ?severity = function
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
  | Mule_pass_through { window; min_incoming; ratio_bps } ->
    Rules.mule_pass_through ?severity ~window ~min_incoming ~ratio_bps ()
  | Account_takeover { recent; min_signals; balance_share_bps } ->
    Rules.account_takeover ?severity ~recent ~min_signals ?balance_share_bps ()
  | Mule_fan_in { min_senders; window; max_account_age } ->
    Rules.mule_fan_in ?severity ~min_senders ~window ~max_account_age ()
  | New_account_payout { max_age; above } ->
    Rules.new_account_payout ?severity ~max_age ~above ()
  | App_first_large_payment { new_within; multiple } ->
    Rules.app_first_large_payment ?severity ~new_within ~multiple ()
  | Vop_not_matched -> Rules.vop_not_matched ?severity ()
  | Card_testing { small; count; max_declines; window } ->
    Rules.card_testing ?severity ~small ~count ~max_declines ~window ()
  | App_fraud { new_within; balance_share_bps } ->
    Rules.app_fraud ?severity ~new_within ~balance_share_bps ()
  | Score { model; thresholds } ->
    (* The thresholds pick the severity; an override caps it. *)
    let rule =
      match find_model models model with
      | Some m -> Rules.model_score m thresholds
      | None -> unavailable ~name:"model_score" model
    in
    Option.value_map severity ~default:rule ~f:(fun max -> Rule.cap rule ~max)
  | Sca_tra
      { scheme
      ; observed_fraud_rate_ppm
      ; trusted_beneficiaries_exempt
      ; recent
      ; model
      ; max_score
      } ->
    (match model with
     | Some name when Option.is_none (find_model models name) ->
       unavailable ~name:"sca_tra" name
     | _ ->
       let model =
         Option.bind model ~f:(find_model models) |> Option.map ~f:(fun m -> m, max_score)
       in
       Rules.sca_tra
         ?severity
         ~scheme
         ~observed_fraud_rate_ppm
         ~trusted_beneficiaries_exempt
         ~recent
         ?model
         ())
  | Manual_review { reason } ->
    Rule.always
      ~name:"manual_review"
      ~severity:(Option.value severity ~default:Severity.Review)
      ~code:Manual_review
      ~reason
  (* The outermost override wins: [(Severity Block (Severity Review x))] is [Block]. *)
  | Shadow spec -> Rule.cap (to_rule_with ~models ?severity spec) ~max:Allow
  | Severity (outer, spec) ->
    to_rule_with ~models ~severity:(Option.value severity ~default:outer) spec
;;

let to_rule ?(models = []) spec = to_rule_with ~models spec
