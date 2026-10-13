open! Core

let validate s =
  if String.is_empty s
  then Or_error.error_string "tier: empty name"
  else if String.for_all s ~f:(fun c ->
            Char.is_lowercase c || Char.is_digit c || Char.equal c '-' || Char.equal c '_')
  then Ok s
  else Or_error.error_s [%message "tier: invalid name" (s : string)]
;;

module Stable = struct
  module V1 = struct
    type t = string [@@deriving bin_io, compare, equal, hash, sexp_of]

    let t_of_sexp sexp = Or_error.ok_exn (validate (String.t_of_sexp sexp))
  end
end

module T = struct
  type t = Stable.V1.t [@@deriving bin_io, compare, hash, sexp_of]

  let t_of_sexp = Stable.V1.t_of_sexp
  let of_string s = Or_error.ok_exn (validate s)
  let to_string t = t
  let module_name = "Risk_rules.Tier"
end

include T
include Identifiable.Make (T)

let of_string_or_error = validate

let quickcheck_generator =
  Quickcheck.Generator.of_list [ "basic"; "verified"; "premium"; "business" ]
;;

let quickcheck_observer = String.quickcheck_observer
let quickcheck_shrinker = Quickcheck.Shrinker.empty ()
