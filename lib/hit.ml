open! Core

module Stable = struct
  module V1 = struct
    type t =
      { rule : string
      ; severity : Severity.Stable.V1.t
      ; reason : string
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
