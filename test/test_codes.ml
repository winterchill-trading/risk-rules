open! Core
open Risk_rules

let%expect_test "country codes" =
  List.iter [ "DE"; "fr"; "D"; "DEU"; "1A" ] ~f:(fun s ->
    print_s [%sexp (Country.of_string_or_error s : Country.t Or_error.t)]);
  [%expect
    {|
    (Ok DE)
    (Ok FR)
    (Error ("country: expected ISO 3166 alpha-2" (s D)))
    (Error ("country: expected ISO 3166 alpha-2" (s DEU)))
    (Error ("country: expected ISO 3166 alpha-2" (s 1A)))
    |}];
  print_endline [%bin_digest: Country.Stable.V1.t];
  [%expect {| d9a8da25d5656b016fb4dbdc2e4197fb |}]
;;

let%expect_test "merchant category codes keep four digits" =
  List.iter [ 742; 7995; 10_000; -1 ] ~f:(fun n ->
    print_s [%sexp (Mcc.of_int_or_error n : Mcc.t Or_error.t)]);
  [%expect
    {|
    (Ok 742)
    (Ok 7995)
    (Error ("mcc: expected 0000-9999" (n 10000)))
    (Error ("mcc: expected 0000-9999" (n -1)))
    |}];
  print_s
    [%sexp
      (Mcc.of_string "0742" : Mcc.t), (Mcc.t_of_sexp (Sexp.of_string "6051") : Mcc.t)];
  [%expect {| (742 6051) |}];
  print_endline [%bin_digest: Mcc.Stable.V1.t];
  [%expect {| 698cfa4093fe5e51523842d37b92aeac |}]
;;

let%test_unit "mcc string round trip" =
  Quickcheck.test Mcc.quickcheck_generator ~sexp_of:Mcc.sexp_of_t ~f:(fun m ->
    [%test_eq: Mcc.t] m (Mcc.of_string (Mcc.to_string m)))
;;
