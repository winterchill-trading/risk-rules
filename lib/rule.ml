open! Core

type 'ctx t =
  { name : string
  ; severity : Severity.t
  ; predicate : 'ctx -> string option
  }

let sexp_of_t _ { name; severity; predicate = _ } =
  [%sexp { name : string; severity : Severity.t }]
;;

let create ~name ~severity predicate = { name; severity; predicate }
let name t = t.name
let severity t = t.severity

let check t ctx =
  Option.map (t.predicate ctx) ~f:(fun reason ->
    { Hit.rule = t.name; severity = t.severity; reason })
;;

let contramap t ~f = { t with predicate = (fun ctx -> t.predicate (f ctx)) }
let always ~name ~severity ~reason = create ~name ~severity (fun _ -> Some reason)
