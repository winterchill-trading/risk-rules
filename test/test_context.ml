open! Core
open Risk_rules
open Fixtures

let%expect_test "transfer context takes the IBAN country unless overridden" =
  let show subject =
    match subject with
    | Context.Subject.Transfer t ->
      print_s [%sexp (t.beneficiary_country : Country.t option)]
    | Card_auth _ -> assert false
  in
  show (transfer (eur "1.00"));
  show (transfer ~country:(country "FR") (eur "1.00"));
  show (transfer ~beneficiary:(wallet_beneficiary ()) (btc "0.10000000"));
  [%expect {|
    (DE)
    (FR)
    ()
    |}]
;;

let%expect_test "only outgoing transfers to a beneficiary make a context" =
  let incoming =
    Payments_core.Transfer.incoming
      ~id:(Payments_core.Transfer.Id.of_string "in-1")
      ~rail:Sepa_credit
      ~account:(Ledger.Account_id.of_string "customer:1/eur")
      ~from:(External { name = "Payer"; detail = "DE89370400440532013000" })
      ~amount:(eur "5.00")
      ~status:Settled
      ~now:t0
      ()
    |> Or_error.ok_exn
  in
  print_s
    [%sexp (Context.Transfer.create incoming |> Or_error.map ~f:ignore : unit Or_error.t)];
  [%expect
    {|
    (Error
     ("context: expected an outgoing transfer to a beneficiary" (transfer in-1)))
    |}];
  print_s
    [%sexp (Context.Past_transfer.of_transfer incoming : Context.Past_transfer.t option)];
  [%expect {| () |}]
;;

let%expect_test "past transfers count while live, not once failed" =
  let ok = Or_error.ok_exn in
  let d = draft (eur "40.00") in
  let at m = Time_ns.add t0 (minutes m) in
  let submitted = ok (Payments_core.Transfer.submit d ~at:(at 1) ()) in
  let failed =
    ok
      (Payments_core.Transfer.transition
         submitted
         ~to_:(Failed Insufficient_funds)
         ~at:(at 2))
  in
  List.iter
    [ "draft", d; "submitted", submitted; "failed", failed ]
    ~f:(fun (label, t) ->
      print_s
        [%sexp
          (label : string)
          , (Context.Past_transfer.of_transfer t : Context.Past_transfer.t option)]);
  [%expect
    {|
    (draft ())
    (submitted
     (((at "2026-10-13 12:00:00Z") (amount "40.00 EUR") (beneficiary (ben-1)))))
    (failed ())
    |}]
;;

let%expect_test "countries and history window" =
  let geo = { Context.Geo.ip_country = Some (country "DE"); residence = None } in
  let ctx =
    context
      ~geo
      ~history:[ past (hours 1) (eur "1.00"); past (hours 30) (eur "2.00") ]
      (transfer (eur "3.00"))
  in
  (* The IBAN is German too: listed once. *)
  print_s [%sexp (Context.countries ctx : Country.t list)];
  print_s [%sexp (List.length (Context.history_within ctx ~window:(hours 24)) : int)];
  print_s [%sexp (Context.balance ctx Money.Currency.eur : Money.Amount.t option)];
  print_s [%sexp (Context.balance ctx Money.Currency.btc : Money.Amount.t option)];
  [%expect {|
    (DE)
    1
    ("10000.00 EUR")
    ()
    |}]
;;

let%expect_test "context round trips and digest" =
  let ctx = context ~history:[ past (hours 1) (eur "1.00") ] (transfer (eur "3.00")) in
  assert (Context.equal ctx (Context.t_of_sexp (Context.sexp_of_t ctx)));
  assert (
    Context.equal
      ctx
      (Binable.of_string
         (module Context.Stable.V1)
         (Binable.to_string (module Context.Stable.V1) ctx)));
  print_endline [%bin_digest: Context.Stable.V1.t];
  [%expect {| 91267da548d5edfa27e1918a12bf0b60 |}]
;;
