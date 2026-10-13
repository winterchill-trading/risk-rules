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
  | Review -> 10
  | Block -> 20
;;

let evaluate =
  Command.basic
    ~summary:"Evaluate a context sexp against a policy and print the decision"
    ~readme:(fun () ->
      "The context file holds one Risk_rules.Context.t sexp (see \
       examples/context-transfer.sexp). Exit code: 0 allow, 10 review, 20 block.")
    (let%map_open.Command path = policy_flag
     and context = anon ("CONTEXT" %: string)
     and sexp = flag "-sexp" no_arg ~doc:" print the decision as a sexp" in
     fun () ->
       let policy = or_exit (Policy.load path) in
       let ctx =
         or_exit
           (Or_error.try_with (fun () ->
              Sexp.load_sexp_conv_exn context Context.t_of_sexp))
       in
       let decision = Policy.evaluate policy ctx in
       if sexp
       then print_s [%sexp (decision : Decision.t)]
       else print_endline (Decision.to_string_hum decision);
       Stdlib.exit (exit_code decision))
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"Provider-neutral transfer and card risk rules"
       [ "check-policy", check_policy; "evaluate", evaluate ])
;;
