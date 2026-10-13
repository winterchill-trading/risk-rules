open! Core

module Stable = struct
  module V1 = struct
    module T = struct
      type t =
        | Limit_per_transfer
        | Limit_daily
        | Limit_monthly
        | Limit_window
        | Velocity_out
        | New_beneficiary_cooldown
        | Structuring
        | Geo_blocked
        | Geo_high_risk
        | Travel_rule_self_hosted
        | Card_mcc_blocked
        | Card_online_disabled
        | Manual_review
        | Mule_pass_through
        | Account_takeover_signals
        | App_new_beneficiary_balance
        | Mule_fan_in
        | New_account_payout
        | Vop_not_matched
        | Card_testing
        | App_first_large_payment
        | Sca_exempt
        | Score_high
        | Score_unavailable
        | Sca_required
        | Rule_error
        | Unknown_tier
        | Custom of string
      [@@deriving bin_io, compare, equal, hash, quickcheck, sexp]
    end

    include T

    let custom_prefix = "CUSTOM_"

    let to_string = function
      | Custom name -> custom_prefix ^ name
      | code -> String.uppercase (Sexp.to_string (T.sexp_of_t code))
    ;;

    let of_string s =
      match String.chop_prefix s ~prefix:custom_prefix with
      | Some name when not (String.is_empty name) -> Custom name
      | Some _ | None ->
        (match String.capitalize (String.lowercase s) with
         | "Custom" -> raise_s [%message "reason code: Custom needs a name" s]
         | ctor -> T.t_of_sexp (Sexp.Atom ctor))
    ;;

    let sexp_of_t t = Sexp.Atom (to_string t)

    let t_of_sexp = function
      | Sexp.Atom s -> of_string s
      | sexp -> raise_s [%message "reason code: expected an atom" (sexp : Sexp.t)]
    ;;
  end
end

include Stable.V1

let builtin =
  [ Limit_per_transfer
  ; Limit_daily
  ; Limit_monthly
  ; Limit_window
  ; Velocity_out
  ; New_beneficiary_cooldown
  ; Structuring
  ; Geo_blocked
  ; Geo_high_risk
  ; Travel_rule_self_hosted
  ; Card_mcc_blocked
  ; Card_online_disabled
  ; Manual_review
  ; Mule_pass_through
  ; Account_takeover_signals
  ; App_new_beneficiary_balance
  ; Mule_fan_in
  ; New_account_payout
  ; Vop_not_matched
  ; Card_testing
  ; App_first_large_payment
  ; Sca_exempt
  ; Score_high
  ; Score_unavailable
  ; Sca_required
  ; Rule_error
  ; Unknown_tier
  ]
;;

let typology : t -> Typology.t = function
  | Limit_per_transfer | Limit_daily | Limit_monthly | Limit_window -> Limits
  | Velocity_out -> Velocity
  | New_beneficiary_cooldown | Account_takeover_signals -> Account_takeover
  | Structuring -> Structuring
  | Geo_blocked | Geo_high_risk -> Sanctions_geography
  | Travel_rule_self_hosted -> Travel_rule
  | Card_mcc_blocked | Card_online_disabled | Card_testing -> Card_controls
  | Mule_pass_through | Mule_fan_in | New_account_payout -> Money_mule
  | App_new_beneficiary_balance | App_first_large_payment | Vop_not_matched -> App_fraud
  | Score_high | Score_unavailable -> Model_score
  | Sca_required | Sca_exempt -> Strong_authentication
  | Manual_review | Rule_error | Unknown_tier | Custom _ -> Operational
;;

let description = function
  | Limit_per_transfer -> "single transfer above the tier's per-transfer cap"
  | Limit_daily -> "rolling 24 hour outgoing total above the tier's cap"
  | Limit_monthly -> "rolling 30 day outgoing total above the tier's cap"
  | Limit_window -> "outgoing total in a custom rolling window above its cap"
  | Velocity_out -> "too many outgoing transfers in a short window"
  | New_beneficiary_cooldown -> "large transfer to a beneficiary added recently"
  | Structuring -> "repeated round or just-below-threshold amounts"
  | Geo_blocked -> "a sanctioned or blocked country is involved"
  | Geo_high_risk -> "a high-risk country is involved"
  | Travel_rule_self_hosted ->
    "crypto withdrawal to an unverified self-hosted wallet needs travel-rule data"
  | Card_mcc_blocked -> "merchant category blocked"
  | Card_online_disabled -> "online card payment while the cardholder disabled them"
  | Manual_review -> "every operation of this tier is reviewed"
  | Mule_pass_through -> "funds received and sent on quickly (money mule pattern)"
  | Account_takeover_signals -> "several account takeover signals at once"
  | App_new_beneficiary_balance ->
    "most of the balance to a new beneficiary (push payment scam pattern)"
  | Mule_fan_in -> "many distinct payers into a young account (money mule pattern)"
  | New_account_payout -> "large payout from a newly opened account"
  | Vop_not_matched -> "verification of payee did not match the beneficiary name"
  | Card_testing -> "many small or declined card authorisations in a short time"
  | App_first_large_payment ->
    "payment far above the customer's usual amount to a new beneficiary"
  | Sca_exempt -> "strong customer authentication exemption applied (informational)"
  | Score_high -> "model fraud score above the policy threshold"
  | Score_unavailable -> "the scoring model named by the policy is not loaded"
  | Sca_required -> "strong customer authentication needed, no exemption applies"
  | Rule_error -> "a rule raised; failing closed"
  | Unknown_tier -> "the customer's tier has no rules in the policy"
  | Custom name -> "custom rule " ^ name
;;

let check_message = "We need to check this payment before it can be sent."

let customer_message = function
  | Limit_per_transfer -> "This payment is above your limit for a single payment."
  | Limit_daily -> "This payment would take you over your daily limit."
  | Limit_monthly -> "This payment would take you over your monthly limit."
  | Limit_window -> "This payment would take you over your account limit."
  | Velocity_out ->
    "You have made several payments in a short time. Please try again later."
  | New_beneficiary_cooldown ->
    "Payments to a newly added payee are limited for a short time. Please try a smaller \
     amount or try again later."
  | Geo_blocked -> "We cannot make payments involving this country."
  | Travel_rule_self_hosted ->
    "Please confirm you own this wallet, or tell us who owns it, before we send this \
     payment."
  | Card_mcc_blocked -> "Your card cannot be used at this type of merchant."
  | Card_online_disabled ->
    "Online payments are switched off for this card. You can switch them on in the app."
  | Sca_required -> "Please confirm this payment in the app."
  | Sca_exempt -> "No confirmation needed."
  | Vop_not_matched ->
    "The name you entered does not match the account holder. Please check the payee \
     before sending: if you were asked to pay this account by someone you have not met, \
     it may be a scam."
  | Card_testing -> "Your card has been paused for your protection. Please check the app."
  (* Push payment scams target the customer as a victim, so a warning helps rather than
     tips anyone off. *)
  | App_new_beneficiary_balance | App_first_large_payment ->
    "This payment matches a common scam: no bank will ever ask you to move your money to \
     a new account to keep it safe. We need to check it before it is sent."
  | Unknown_tier | Rule_error | Score_unavailable ->
    "We cannot process this payment right now. Please try again later."
  (* Suspicion typologies: neutral wording, see the interface comment. *)
  | Structuring
  | Geo_high_risk
  | Manual_review
  | Mule_pass_through
  | Account_takeover_signals
  | Mule_fan_in
  | New_account_payout
  | Score_high
  | Custom _ -> check_message
;;
