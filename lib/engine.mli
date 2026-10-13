(** Evaluate a rule list against a context. Pure: no I/O, no clock. *)

open! Core

(** Runs every rule (no short-circuit, so operators see all reasons), keeps the hits in
    rule order, and takes the worst severity.

    A rule that raises is reported as a [Block] hit named after the rule with the
    exception as its reason: a broken rule must fail closed rather than let a payment
    through unchecked. *)
val evaluate : 'ctx Rule.t list -> 'ctx -> Decision.t
