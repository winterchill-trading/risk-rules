open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Limits
      | Velocity
      | Structuring
      | Money_mule
      | Account_takeover
      | App_fraud
      | Sanctions_geography
      | Travel_rule
      | Card_controls
      | Model_score
      | Strong_authentication
      | Operational
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t =
  | Limits
  | Velocity
  | Structuring
  | Money_mule
  | Account_takeover
  | App_fraud
  | Sanctions_geography
  | Travel_rule
  | Card_controls
  | Model_score
  | Strong_authentication
  | Operational
[@@deriving sexp, compare, equal, hash, enumerate, quickcheck]

let to_string t = String.lowercase (Sexp.to_string (sexp_of_t t))
