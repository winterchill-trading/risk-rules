(** How strongly a rule objects to an operation.

    Ordered [Allow < Review < Block]; the engine keeps the worst one. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      | Allow
      | Review
      | Block
    [@@deriving bin_io, sexp, compare, equal, hash, quickcheck]
  end
end

type t = Stable.V1.t =
  | Allow
  | Review
  | Block
[@@deriving sexp, compare, equal, hash, quickcheck, enumerate]

include Comparable.S with type t := t

(** [worst a b] is the more severe of the two. *)
val worst : t -> t -> t

val to_string : t -> string
