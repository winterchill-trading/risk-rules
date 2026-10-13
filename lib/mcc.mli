(** ISO 18245 merchant category code, four digits (e.g. [7995] betting). *)

open! Core

module Stable : sig
  module V1 : sig
    type t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t [@@deriving quickcheck]

include Identifiable.S with type t := t

val of_int_or_error : int -> t Or_error.t
val of_int_exn : int -> t
val to_int : t -> int
