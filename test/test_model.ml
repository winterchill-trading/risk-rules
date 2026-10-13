open! Core
open Risk_rules
open Fixtures

let%expect_test "score validation" =
  let show value reasons =
    print_s [%sexp (Model.Score.create ~value ~reasons : Model.Score.t Or_error.t)]
  in
  show 0.5 [ "a", 0.1; "b", 0.7 ];
  show 1.5 [];
  show Float.nan [];
  show 0.2 [ "x", Float.infinity ];
  [%expect
    {|
    (Ok ((value 0.5) (reasons ((b 0.7) (a 0.1)))))
    (Error ("model score outside [0, 1]" (value 1.5)))
    (Error ("model score outside [0, 1]" (value NAN)))
    (Error ("model reason with a non-finite contribution" x (contribution INF)))
    |}]
;;

let model =
  Model.logistic
    ~name:"baseline"
    ~version:"2026-10-13"
    ~intercept:(-4.)
    ~weights:
      [ "amount_to_balance", 3.
      ; "new_device", 1.5
      ; "beneficiary_age_hours", -0.01
      ; "pass_through_ratio_24h", 1.
      ]
    ()
  |> Or_error.ok_exn
;;

let%expect_test "logistic baseline" =
  (* Printed to 6 decimals: [exp] may differ in the last bits between the macOS and glibc
     maths libraries. *)
  let score ctx =
    let s = Model.score model (Features.of_context ctx) in
    printf "%.6f" s.value;
    List.iter s.reasons ~f:(fun (code, c) -> printf " %s=%.6f" code c);
    print_endline ""
  in
  score (context (transfer (eur "10.00")));
  score
    (context
       ~balances:[ eur "1000.00" ]
       ~session:{ Context.Session.unknown with new_device = true }
       (transfer ~beneficiary:(beneficiary ~first_seen:(ago (hours 1)) ()) (eur "950.00")));
  [%expect
    {|
    0.000000 amount_to_balance=0.003000
    0.584191 amount_to_balance=2.850000 new_device=1.500000
    |}];
  print_s
    [%sexp
      (Model.logistic
         ~name:"bad"
         ~version:"0"
         ~intercept:0.
         ~weights:[ "no_such_feature", 1. ]
         ()
       |> Or_error.map ~f:Model.name
       : string Or_error.t)];
  [%expect {| (Error ("logistic model: unknown feature" no_such_feature)) |}]
;;

let%test_unit "logistic scores are probabilities whatever the features" =
  let gen =
    Quickcheck.Generator.map2
      (Float.gen_incl 0. 1e12)
      (Float.gen_incl (-1e6) 1e6)
      ~f:(fun amount weight -> amount, weight)
  in
  Quickcheck.test gen ~sexp_of:[%sexp_of: float * float] ~f:(fun (amount, weight) ->
    let m =
      Model.logistic ~name:"q" ~version:"0" ~intercept:0. ~weights:[ "amount", weight ] ()
      |> Or_error.ok_exn
    in
    let cents = Float.iround_down_exn (Float.min amount 1e10) + 1 in
    let ctx =
      context
        ~balances:[]
        (transfer (Money.Amount.of_minor_units_int Money.Currency.eur cents))
    in
    let s = Model.score m (Features.of_context ctx) in
    assert (Float.(s.value >= 0. && s.value <= 1.)))
;;
