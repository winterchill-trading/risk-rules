(** One triggered rule: which rule, how severe, why, and the evidence an auditor needs to
    reproduce the judgement. *)

open! Core

module Stable : sig
  module V1 : sig
    type t =
      { rule : string (** the rule's name in the policy *)
      ; severity : Severity.Stable.V1.t
      ; code : Reason_code.Stable.V1.t
      ; typology : Typology.Stable.V1.t
      ; reason : string
      (** detailed, for operators and the audit log; never shown to customers *)
      ; evidence : (string * string) list
      (** the inputs the rule compared, e.g. [("limit", "1000.00 EUR")] *)
      }
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t =
  { rule : string
  ; severity : Severity.t
  ; code : Reason_code.t
  ; typology : Typology.t
  ; reason : string
  ; evidence : (string * string) list
  }
[@@deriving sexp, compare, equal, hash, quickcheck]
