open! Core

module Stable = struct
  module V1 = struct
    type t =
      { rule : string
      ; severity : Severity.Stable.V1.t
      ; code : Reason_code.Stable.V1.t
      ; typology : Typology.Stable.V1.t
      ; reason : string
      ; evidence : (string * string) list [@sexp.list]
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
  ; evidence : (string * string) list [@sexp.list]
  }
[@@deriving sexp, compare, equal, hash, quickcheck]
