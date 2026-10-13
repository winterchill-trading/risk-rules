(** How strongly a rule objects to an operation.

    Ordered [Allow < Challenge < Review < Block]; the engine keeps the worst
    one. [Challenge] lets the operation through once the customer passes
    strong customer authentication (a step-up); [Review] holds it for an
    operator; [Block] refuses it. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      | Allow
      | Challenge
      | Review
      | Block
    [@@deriving bin_io, sexp, compare, equal, hash, quickcheck]
  end
end

type t = Stable.V1.t =
  | Allow
  | Challenge
  | Review
  | Block
[@@deriving sexp, compare, equal, hash, quickcheck, enumerate]

include Comparable.S with type t := t

(** [worst a b] is the more severe of the two. *)
val worst : t -> t -> t

val to_string : t -> string
