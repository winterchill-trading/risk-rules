open! Core

let validate n =
  if n >= 0 && n <= 9999
  then Ok n
  else Or_error.error_s [%message "mcc: expected 0000-9999" (n : int)]
;;

module Stable = struct
  module V1 = struct
    type t = int [@@deriving bin_io, compare, equal, hash, sexp_of]

    let t_of_sexp sexp = Or_error.ok_exn (validate (Int.t_of_sexp sexp))
  end
end

module T = struct
  type t = Stable.V1.t [@@deriving bin_io, compare, hash, sexp_of]

  let t_of_sexp = Stable.V1.t_of_sexp

  (* Always four digits: "0742" (veterinary services) keeps its leading zero. *)
  let to_string t = sprintf "%04d" t

  let of_string s =
    if String.length s = 4 && String.for_all s ~f:Char.is_digit
    then Int.of_string s
    else raise_s [%message "mcc: expected four digits" (s : string)]
  ;;

  let module_name = "Risk_rules.Mcc"
end

include T
include Identifiable.Make (T)

let of_int_or_error = validate
let of_int_exn n = Or_error.ok_exn (validate n)
let to_int t = t
let quickcheck_generator = Int.gen_incl 0 9999
let quickcheck_observer = Int.quickcheck_observer
let quickcheck_shrinker = Quickcheck.Shrinker.empty ()
