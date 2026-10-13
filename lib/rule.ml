open! Core

module Outcome = struct
  type t =
    { severity : Severity.t
    ; code : Reason_code.t
    ; reason : string
    ; evidence : (string * string) list
    }
  [@@deriving sexp_of]
end

type 'ctx t =
  { name : string
  ; severity : Severity.t
  ; check : 'ctx -> Outcome.t option
  }

let sexp_of_t _ { name; severity; check = _ } =
  [%sexp { name : string; severity : Severity.t }]
;;

let create ~name ~severity ~code ?(evidence = fun _ -> []) predicate =
  { name
  ; severity
  ; check =
      (fun ctx ->
        Option.map (predicate ctx) ~f:(fun reason ->
          { Outcome.severity; code; reason; evidence = evidence ctx }))
  }
;;

let create_graded ~name ~max_severity check =
  { name
  ; severity = max_severity
  ; check =
      (fun ctx ->
        Option.map (check ctx) ~f:(fun (outcome : Outcome.t) ->
          { outcome with severity = Severity.min outcome.severity max_severity }))
  }
;;

let name t = t.name
let severity t = t.severity

let check t ctx =
  Option.map (t.check ctx) ~f:(fun { Outcome.severity; code; reason; evidence } ->
    { Hit.rule = t.name
    ; severity
    ; code
    ; typology = Reason_code.typology code
    ; reason
    ; evidence
    })
;;

let contramap t ~f = { t with check = (fun ctx -> t.check (f ctx)) }

let always ~name ~severity ~code ~reason =
  create ~name ~severity ~code (fun _ -> Some reason)
;;
