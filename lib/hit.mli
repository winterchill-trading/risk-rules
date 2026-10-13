(** One triggered rule: which rule, how severe, and why. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      { rule : string (** the rule's name *)
      ; severity : Severity.Stable.V1.t
      ; reason : string (** human readable, shown to operators *)
      }
    [@@deriving bin_io, sexp, compare, equal, hash, quickcheck]
  end
end

type t = Stable.V1.t =
  { rule : string
  ; severity : Severity.t
  ; reason : string
  }
[@@deriving sexp, compare, equal, hash, quickcheck]
