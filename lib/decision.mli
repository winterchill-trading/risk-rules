(** The outcome of evaluating a rule set: the worst severity among the triggered rules,
    and every triggered rule in evaluation order. *)

open! Core

module Stable : sig
  module V1 : sig
    type t = private
      { severity : Severity.Stable.V1.t
      ; hits : Hit.Stable.V1.t list
      }
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t = private
  { severity : Severity.t
  ; hits : Hit.t list
  }
[@@deriving sexp, compare, equal, hash]

(** No rule triggered. *)
val allow : t

(** [of_hits hits] derives the severity from the hits ([Allow] when empty). The record is
    private so the severity can never disagree with the hits. *)
val of_hits : Hit.t list -> t

val is_allowed : t -> bool
val needs_review : t -> bool
val is_blocked : t -> bool

(** Concatenate hits; the severity is the worst of both. *)
val combine : t -> t -> t

(** One line per hit, for logs and operator screens. *)
val to_string_hum : t -> string
