open! Core
open Risk_rules

(* The engine is generic over the context; an int stands in for a payment amount here so
   these tests need no domain types. *)
let over ~name ~severity limit =
  Rule.create ~name ~severity ~code:(Custom name) (fun amount ->
    Option.some_if (amount > limit) (sprintf "%d > %d" amount limit))
;;

let rules =
  [ over ~name:"soft_cap" ~severity:Review 100
  ; over ~name:"hard_cap" ~severity:Block 1_000
  ; over ~name:"note" ~severity:Allow 10
  ]
;;

let show amount = print_endline (Decision.to_string_hum (Engine.evaluate rules amount))

let%expect_test "worst severity wins and every hit is listed" =
  show 5;
  [%expect {| allow |}];
  show 50;
  [%expect {|
    allow
      note [allow] CUSTOM_note: 50 > 10
    |}];
  show 500;
  [%expect
    {|
    review
      soft_cap [review] CUSTOM_soft_cap: 500 > 100
      note [allow] CUSTOM_note: 500 > 10
    |}];
  show 5_000;
  [%expect
    {|
    block
      soft_cap [review] CUSTOM_soft_cap: 5000 > 100
      hard_cap [block] CUSTOM_hard_cap: 5000 > 1000
      note [allow] CUSTOM_note: 5000 > 10
    |}]
;;

let%expect_test "a raising rule blocks" =
  let boom =
    Rule.create ~name:"boom" ~severity:Allow ~code:(Custom "BOOM") (fun _ ->
      failwith "bad config")
  in
  print_s [%sexp (Engine.evaluate [ boom ] 1 : Decision.t)];
  [%expect
    {|
    ((severity Block)
     (hits
      (((rule boom) (severity Block) (code RULE_ERROR) (typology Operational)
        (reason "rule raised: (Failure \"bad config\")")))))
    |}]
;;

let%expect_test "decision sexp round trip re-derives severity" =
  let d = Engine.evaluate rules 500 in
  let sexp = Decision.sexp_of_t d in
  assert (Decision.equal d (Decision.t_of_sexp sexp));
  (* A tampered severity is ignored on read. *)
  let tampered =
    Sexp.of_string
      "((severity Allow) (hits (((rule hard_cap) (severity Block) (code LIMIT_DAILY) \
       (typology Limits) (reason x)))))"
  in
  print_s [%sexp ((Decision.t_of_sexp tampered).severity : Severity.t)];
  [%expect {| Block |}]
;;

let%expect_test "decision bin digest" =
  print_endline [%bin_digest: Decision.Stable.V1.t];
  print_endline [%bin_digest: Hit.Stable.V1.t];
  [%expect
    {|
    4f02b4e3bd245cb6c8cf214a1f614ace
    c0bd3df451427f2c8cf4c628e70a9fbd
    |}]
;;

(* Property: adding a rule anywhere in the list never lowers the decision's severity and
   never drops an existing hit. *)
module Spec = struct
  type t =
    { severity : Severity.t
    ; limit : int
    }
  [@@deriving sexp, quickcheck]

  let to_rule i { severity; limit } = over ~name:(sprintf "r%d" i) ~severity limit
end

let%test_unit "adding a rule never lowers the severity" =
  Quickcheck.test
    ~sexp_of:[%sexp_of: Spec.t list * Spec.t * int * int]
    [%quickcheck.generator:
      Spec.t list * Spec.t * int * [%custom Int.gen_incl 0 1_000_000]]
    ~f:(fun (specs, extra, position, amount) ->
      let rules = List.mapi specs ~f:Spec.to_rule in
      let extra = Spec.to_rule (List.length specs) extra in
      let position = Int.rem (Int.abs position) (List.length rules + 1) in
      let before = Engine.evaluate rules amount in
      let after =
        Engine.evaluate
          (List.take rules position @ [ extra ] @ List.drop rules position)
          amount
      in
      [%test_pred: Severity.t * Severity.t]
        (fun (b, a) -> Severity.( >= ) a b)
        (before.severity, after.severity);
      [%test_pred: Hit.t list * Hit.t list]
        (fun (b, a) -> List.for_all b ~f:(List.mem a ~equal:Hit.equal))
        (before.hits, after.hits))
;;
