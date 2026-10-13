open! Core

module Repr = struct
  type t =
    { all_tiers : Rule_spec.t list [@sexp.list]
    ; tiers : (Tier.t * Rule_spec.t list) list [@sexp.list]
    }
  [@@deriving sexp, compare, equal]
end

type t = Repr.t [@@deriving compare, equal, sexp_of]

let create ~all_tiers ~tiers =
  let open Or_error.Let_syntax in
  let%bind () =
    match List.find_a_dup (List.map tiers ~f:fst) ~compare:Tier.compare with
    | Some tier -> Or_error.error_s [%message "policy: tier listed twice" (tier : Tier.t)]
    | None -> Ok ()
  in
  let%map () =
    Or_error.combine_errors_unit
      (List.map (all_tiers @ List.concat_map tiers ~f:snd) ~f:Rule_spec.validate)
  in
  { Repr.all_tiers; tiers }
;;

let t_of_sexp sexp =
  let { Repr.all_tiers; tiers } = Repr.t_of_sexp sexp in
  Or_error.ok_exn (create ~all_tiers ~tiers)
;;

let all_tiers (t : t) = t.all_tiers
let tiers (t : t) = List.map t.tiers ~f:fst

let specs_for (t : t) tier =
  match List.Assoc.find t.tiers tier ~equal:Tier.equal with
  | Some specs -> Ok (t.all_tiers @ specs)
  | None -> Or_error.error_s [%message "policy: unknown tier" (tier : Tier.t)]
;;

let rules_for t tier = Or_error.map (specs_for t tier) ~f:(List.map ~f:Rule_spec.to_rule)

let evaluate t (ctx : Context.t) =
  match rules_for t ctx.tier with
  | Ok rules -> Engine.evaluate rules ctx
  | Error _ ->
    Decision.of_hits
      [ { rule = "unknown_tier"
        ; severity = Block
        ; reason = sprintf "no rules for tier %s" (Tier.to_string ctx.tier)
        }
      ]
;;

let of_string text =
  Or_error.try_with_join (fun () ->
    let sexp = Sexp.of_string text in
    let { Repr.all_tiers; tiers } = Repr.t_of_sexp sexp in
    create ~all_tiers ~tiers)
;;

let load path =
  Or_error.try_with_join (fun () -> of_string (In_channel.read_all path))
  |> Or_error.tag_s ~tag:[%message "policy: loading" path]
;;
