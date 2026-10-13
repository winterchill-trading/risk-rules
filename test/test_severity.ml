open! Core
open Risk_rules

let%expect_test "severity order and digest" =
  print_s [%sexp (List.sort ~compare:Severity.compare Severity.all : Severity.t list)];
  print_endline [%bin_digest: Severity.Stable.V1.t];
  [%expect {|
    (Allow Review Block)
    d93feac9a65338e0a1db6cc42af66a08
    |}]
;;

let%expect_test "worst" =
  List.iter Severity.all ~f:(fun a ->
    List.iter Severity.all ~f:(fun b ->
      printf
        "%s %s -> %s\n"
        (Severity.to_string a)
        (Severity.to_string b)
        (Severity.to_string (Severity.worst a b))));
  [%expect
    {|
    allow allow -> allow
    allow review -> review
    allow block -> block
    review allow -> review
    review review -> review
    review block -> block
    block allow -> block
    block review -> block
    block block -> block
    |}]
;;
