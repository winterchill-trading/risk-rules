(** A fraud scoring model, as the rule engine sees it.

    Implementations live elsewhere (the risk-models repo trains and ships them); here a
    model is a pure, synchronous function from {!Features.t} to a score in [0, 1] with
    reason codes. A model that needs I/O must be wrapped by the caller (score first, then
    put the result in a model that returns it), so evaluation stays pure and replayable. *)

open! Core

module Score : sig
  type t = private
    { value : float (** in [0, 1]; higher is riskier *)
    ; reasons : (string * float) list
    (** reason codes with their contribution, largest first, e.g. feature names for a
        linear model *)
    }
  [@@deriving sexp_of, compare, equal]

  (** Fails on a value outside [0, 1] or NaN, and on a non-finite contribution. Reasons
      are sorted by contribution, largest first. *)
  val create : value:float -> reasons:(string * float) list -> t Or_error.t
end

module type S = sig
  val name : string
  val version : string

  (** Must not raise for any feature record; [Engine] fails closed if it does. *)
  val score : Features.t -> Score.t
end

type t = (module S)

val name : t -> string
val version : t -> string
val score : t -> Features.t -> Score.t

(** Always the same score; for tests and for wiring checks. *)
val constant : name:string -> float -> t

(** A logistic regression over {!Features.to_floats}:
    [sigmoid (intercept + sum weight * x)]. A missing (NaN) feature contributes nothing.
    Reasons are the [top] positive contributions by feature name. Fails on a weight for an
    unknown feature. A baseline and a reference implementation for the model interface,
    not a production model. *)
val logistic
  :  name:string
  -> version:string
  -> intercept:float
  -> weights:(string * float) list
  -> ?top:int
  -> unit
  -> t Or_error.t
