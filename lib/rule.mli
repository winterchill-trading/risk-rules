(** A named predicate over some context ['ctx].

    A rule has a fixed severity. Its check returns [Some reason] when it triggers and
    [None] when it has nothing to say (including when the context is not one it applies
    to, e.g. a card rule looking at a transfer). The context type is a parameter so the
    engine and these combinators do not depend on any domain types. *)

open! Core

type 'ctx t [@@deriving sexp_of]

val create : name:string -> severity:Severity.t -> ('ctx -> string option) -> 'ctx t
val name : _ t -> string
val severity : _ t -> Severity.t

(** [check t ctx] runs the predicate. Exceptions propagate; [Engine.evaluate] is the place
    that turns them into a decision. *)
val check : 'ctx t -> 'ctx -> Hit.t option

(** Run a rule written for one context over another. *)
val contramap : 'a t -> f:('b -> 'a) -> 'b t

(** A rule that triggers on every context; handy for tests and for parking a customer
    under manual review. *)
val always : name:string -> severity:Severity.t -> reason:string -> _ t
