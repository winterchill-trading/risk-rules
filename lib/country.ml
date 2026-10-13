open! Core

let validate s =
  let s = String.uppercase s in
  if String.length s = 2 && String.for_all s ~f:Char.is_uppercase
  then Ok s
  else Or_error.error_s [%message "country: expected ISO 3166 alpha-2" (s : string)]
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
  let module_name = "Risk_rules.Country"
end

include T
include Identifiable.Make (T)

let of_string_or_error = validate

let quickcheck_generator =
  let letter = Quickcheck.Generator.char_uppercase in
  Quickcheck.Generator.map2 letter letter ~f:(fun a b -> String.of_char_list [ a; b ])
;;

let quickcheck_observer = String.quickcheck_observer
let quickcheck_shrinker = Quickcheck.Shrinker.empty ()
