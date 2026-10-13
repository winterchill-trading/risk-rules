open! Core

type t =
  | Required of { reasons : string list }
  | Exempt of Payments_core.Sca.Exemption.t
  | Not_assessed
[@@deriving sexp_of, compare, equal]

let exemption_of_hit (hit : Hit.t) =
  List.Assoc.find hit.evidence Rules.exemption_key ~equal:String.equal
  |> Option.bind ~f:(fun text ->
    Option.try_with (fun () ->
      Payments_core.Sca.Exemption.t_of_sexp (Sexp.of_string text)))
;;

let of_decision (d : Decision.t) =
  let required =
    List.filter d.hits ~f:(fun hit ->
      Reason_code.equal hit.code Sca_required && Severity.( > ) hit.severity Allow)
  in
  match required with
  | _ :: _ -> Required { reasons = List.map required ~f:(fun hit -> hit.reason) }
  | [] ->
    (match
       List.find_map d.hits ~f:(fun hit ->
         if Reason_code.equal hit.code Sca_exempt then exemption_of_hit hit else None)
     with
     | Some e -> Exempt e
     | None -> Not_assessed)
;;
