open! Core
open Risk_rules

let policy_flag = Command.Param.(flag "-policy" (required string) ~doc:"FILE policy sexp")

let or_exit = function
  | Ok x -> x
  | Error err ->
    eprint_s [%sexp (err : Error.t)];
    Stdlib.exit 2
;;

let check_policy =
  Command.basic
    ~summary:"Validate a policy file and list the rules each tier gets"
    (let%map_open.Command path = policy_flag in
     fun () ->
       let policy = or_exit (Policy.load path) in
       List.iter (Policy.tiers policy) ~f:(fun tier ->
         let specs = or_exit (Policy.specs_for policy tier) in
         print_s [%sexp (tier : Tier.t), (specs : Rule_spec.t list)]))
;;

(* Exit codes let shell scripts branch on the outcome: 0 allow, 10 review, 20 block (2 is
   reserved for usage and parse errors). *)
let exit_code (decision : Decision.t) =
  match decision.severity with
  | Allow -> 0
  | Challenge -> 5
  | Review -> 10
  | Block -> 20
;;

let load_context path =
  or_exit (Or_error.try_with (fun () -> Sexp.load_sexp_conv_exn path Context.t_of_sexp))
;;

(* Real models come from the risk-models library; for trying a policy from the shell,
   [-constant-model NAME=SCORE] stands in for one. *)
let constant_model_flag =
  Command.Param.(
    flag
      "-constant-model"
      (listed string)
      ~doc:"NAME=SCORE a model that always returns SCORE (for trying policies)")
  |> Command.Param.map ~f:(fun specs ->
    List.map specs ~f:(fun spec ->
      match String.lsplit2 spec ~on:'=' with
      | Some (name, score) -> Model.constant ~name (Float.of_string score)
      | None -> raise_s [%message "expected NAME=SCORE" spec]))
;;

let features =
  Command.basic
    ~summary:"Print the feature record of a context as JSON (or sexp)"
    (let%map_open.Command context = anon ("CONTEXT" %: string)
     and sexp = flag "-sexp" no_arg ~doc:" print a sexp instead of JSON" in
     fun () ->
       let f = Features.of_context (load_context context) in
       if sexp
       then print_s [%sexp (f : Features.t)]
       else print_endline (Features.to_json f))
;;

let reason_codes =
  Command.basic
    ~summary:"List the reason codes with typology, description and customer message"
    (Command.Param.return (fun () ->
       List.iter Reason_code.builtin ~f:(fun code ->
         printf
           "%s\t%s\t%s\t%s\n"
           (Reason_code.to_string code)
           (Typology.to_string (Reason_code.typology code))
           (Reason_code.description code)
           (Reason_code.customer_message code))))
;;

let evaluate =
  Command.basic
    ~summary:"Evaluate a context sexp against a policy and print the decision"
    ~readme:(fun () ->
      "The context file holds one Risk_rules.Context.t sexp (see \
       examples/context-transfer.sexp). Exit code: 0 allow, 5 challenge, 10 review, 20 \
       block.")
    (let%map_open.Command path = policy_flag
     and context = anon ("CONTEXT" %: string)
     and sexp = flag "-sexp" no_arg ~doc:" print the decision as a sexp"
     and models = constant_model_flag in
     fun () ->
       let policy = or_exit (Policy.load path) in
       let ctx = load_context context in
       let decision = Policy.evaluate ~models policy ctx in
       if sexp
       then print_s [%sexp (decision : Decision.t)]
       else (
         print_endline (Decision.to_string_hum decision);
         Option.iter (Decision.customer_message decision) ~f:(fun m ->
           print_endline ("customer message: " ^ m)));
       Stdlib.exit (exit_code decision))
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"Provider-neutral transfer and card risk rules"
       [ "check-policy", check_policy
       ; "evaluate", evaluate
       ; "features", features
       ; "reason-codes", reason_codes
       ])
;;
