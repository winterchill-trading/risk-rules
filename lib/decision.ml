open! Core

let severity_of_hits hits =
  List.fold hits ~init:Severity.Allow ~f:(fun acc (hit : Hit.t) ->
    Severity.worst acc hit.severity)
;;

module Stable = struct
  module V1 = struct
    module Unchecked = struct
      type t =
        { severity : Severity.Stable.V1.t
        ; hits : Hit.Stable.V1.t list
        }
      [@@deriving bin_io, sexp, compare, equal, hash]
    end

    include Unchecked

    (* Re-derive the severity on read so a hand-edited sexp or an old record cannot carry
       a severity that disagrees with its hits. *)
    let t_of_sexp sexp =
      let { Unchecked.hits; severity = _ } = Unchecked.t_of_sexp sexp in
      { hits; severity = severity_of_hits hits }
    ;;
  end
end

type t = Stable.V1.t =
  { severity : Severity.t
  ; hits : Hit.t list
  }
[@@deriving compare, equal, hash, sexp_of]

let t_of_sexp = Stable.V1.t_of_sexp
let allow = { severity = Allow; hits = [] }
let of_hits hits = { severity = severity_of_hits hits; hits }
let is_allowed t = Severity.equal t.severity Allow
let needs_review t = Severity.equal t.severity Review
let is_blocked t = Severity.equal t.severity Block
let combine a b = of_hits (a.hits @ b.hits)

let to_string_hum t =
  match t.hits with
  | [] -> Severity.to_string t.severity
  | hits ->
    String.concat
      ~sep:"\n"
      (Severity.to_string t.severity
       :: List.map hits ~f:(fun (hit : Hit.t) ->
         sprintf "  %s [%s] %s" hit.rule (Severity.to_string hit.severity) hit.reason))
;;
