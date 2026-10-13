open! Core

let check_one rule ctx =
  match Rule.check rule ctx with
  | hit -> hit
  | exception exn ->
    Some
      { Hit.rule = Rule.name rule
      ; severity = Block
      ; reason = "rule raised: " ^ Exn.to_string_mach exn
      }
;;

let evaluate rules ctx =
  Decision.of_hits (List.filter_map rules ~f:(fun rule -> check_one rule ctx))
;;
