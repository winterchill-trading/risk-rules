(** A named check over some context ['ctx].

    A check returns [None] when it has nothing to say (including when the context is not
    one it applies to, e.g. a card rule looking at a transfer) and an {!Outcome} when it
    triggers. Most rules have one fixed severity and code ({!create}); graded rules such
    as model scores pick the severity per evaluation ({!create_graded}). The context type
    is a parameter so the engine does not depend on any domain types. *)

open! Core

module Outcome : sig
  type t =
    { severity : Severity.t
    ; code : Reason_code.t
    ; reason : string
    ; evidence : (string * string) list
    }
  [@@deriving sexp_of]
end

type 'ctx t [@@deriving sexp_of]

(** A rule with a fixed severity and code; the check returns the detailed reason. *)
val create
  :  name:string
  -> severity:Severity.t
  -> code:Reason_code.t
  -> ?evidence:('ctx -> (string * string) list)
  -> ('ctx -> string option)
  -> 'ctx t

(** A rule whose severity and code depend on the context. [max_severity] is what the rule
    can reach at most, for listings; an outcome above it is capped to it. *)
val create_graded
  :  name:string
  -> max_severity:Severity.t
  -> ('ctx -> Outcome.t option)
  -> 'ctx t

val name : _ t -> string

(** The fixed severity, or the maximum for a graded rule. *)
val severity : _ t -> Severity.t

(** [check t ctx] runs the predicate. Exceptions propagate; [Engine.evaluate] is the place
    that turns them into a decision. *)
val check : 'ctx t -> 'ctx -> Hit.t option

(** Run a rule written for one context over another. *)
val contramap : 'a t -> f:('b -> 'a) -> 'b t

(** A rule that triggers on every context; handy for tests and for parking a customer
    under manual review. *)
val always
  :  name:string
  -> severity:Severity.t
  -> code:Reason_code.t
  -> reason:string
  -> _ t
