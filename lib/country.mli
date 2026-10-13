(** ISO 3166-1 alpha-2 country code, e.g. ["DE"].

    Only the shape is checked (two uppercase ASCII letters); whether a code is assigned
    does not matter to rules, which compare against lists the policy author wrote.
    Lowercase input is accepted and uppercased. *)

open! Core

module Stable : sig
  module V1 : sig
    type t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t [@@deriving quickcheck]

include Identifiable.S with type t := t

val of_string_or_error : string -> t Or_error.t
