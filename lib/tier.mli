(** A customer risk tier, e.g. ["basic"], ["verified"], ["business"].

    Tiers are named by the operator's policy file rather than a closed variant, so adding
    a tier is a config change, not a code change. *)

open! Core

module Stable : sig
  module V1 : sig
    type t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t [@@deriving quickcheck]

(** Non-empty, lowercase ASCII letters, digits, ['-'] and ['_']. *)
include Identifiable.S with type t := t

val of_string_or_error : string -> t Or_error.t
