open! Core

module Stable = struct
  module V1 = struct
    (* Constructor order is the severity order: the derived [compare] relies on it, so
       never reorder or insert in the middle. *)
    type t =
      | Allow
      | Review
      | Block
    [@@deriving bin_io, sexp, compare, equal, hash, quickcheck]
  end
end

module T = struct
  type t = Stable.V1.t =
    | Allow
    | Review
    | Block
  [@@deriving sexp, compare, equal, hash, quickcheck, enumerate]
end

include T
include Comparable.Make (T)

let worst a b = max a b

let to_string = function
  | Allow -> "allow"
  | Review -> "review"
  | Block -> "block"
;;
