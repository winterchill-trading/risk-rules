open! Core
open Risk_rules

let%expect_test "tier names are validated" =
  List.iter [ "basic"; "verified-plus"; "biz_2"; ""; "Basic"; "a b" ] ~f:(fun s ->
    print_s [%sexp (s : string), (Tier.of_string_or_error s : Tier.t Or_error.t)]);
  [%expect
    {|
    (basic (Ok basic))
    (verified-plus (Ok verified-plus))
    (biz_2 (Ok biz_2))
    ("" (Error "tier: empty name"))
    (Basic (Error ("tier: invalid name" (s Basic))))
    ("a b" (Error ("tier: invalid name" (s "a b"))))
    |}];
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Tier.t_of_sexp (Sexp.Atom "NO")) : Tier.t Or_error.t)];
  [%expect {| (Error ("tier: invalid name" (s NO))) |}];
  print_endline [%bin_digest: Tier.Stable.V1.t];
  [%expect {| d9a8da25d5656b016fb4dbdc2e4197fb |}]
;;
