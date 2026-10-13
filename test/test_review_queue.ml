open! Core
open Risk_rules

let at minutes =
  Time_ns.add
    (Time_ns.of_string_with_utc_offset "2026-10-13 09:00:00Z")
    (Time_ns.Span.of_min (Float.of_int minutes))
;;

let review =
  Decision.of_hits
    [ { rule = "velocity"
      ; severity = Review
      ; code = Velocity_out
      ; typology = Velocity
      ; reason = "6 transfers in 10m"
      ; evidence = []
      }
    ]
;;

let ok_exn = Or_error.ok_exn

let show q =
  List.iter (Review_queue.items q) ~f:(fun item ->
    print_s [%sexp (item : Review_queue.Item.t)])
;;

let%expect_test "submit, annotate, decide" =
  let q, a =
    ok_exn
      (Review_queue.submit
         Review_queue.empty
         ~reference:"tr-1"
         ~customer:"c-1"
         ~decision:review
         ~at:(at 0))
  in
  let q, b =
    ok_exn
      (Review_queue.submit
         q
         ~reference:"tr-2"
         ~customer:"c-2"
         ~decision:review
         ~at:(at 1))
  in
  let q =
    ok_exn (Review_queue.annotate q a ~author:"op-1" ~text:"called customer" ~at:(at 2))
  in
  let q = ok_exn (Review_queue.decide q a ~verdict:Approve ~operator:"op-1" ~at:(at 3)) in
  print_s
    [%sexp (List.map (Review_queue.pending q) ~f:(fun i -> i.reference) : string list)];
  [%expect {| (tr-2) |}];
  show q;
  [%expect
    {|
    ((id 1) (reference tr-1) (customer c-1)
     (decision
      ((severity Review)
       (hits
        (((rule velocity) (severity Review) (code VELOCITY_OUT)
          (typology Velocity) (reason "6 transfers in 10m"))))))
     (submitted_at "2026-10-13 09:00:00Z")
     (status
      (Decided (verdict Approve) (operator op-1) (at "2026-10-13 09:03:00Z")))
     (notes
      (((author op-1) (at "2026-10-13 09:02:00Z") (text "called customer")))))
    ((id 2) (reference tr-2) (customer c-2)
     (decision
      ((severity Review)
       (hits
        (((rule velocity) (severity Review) (code VELOCITY_OUT)
          (typology Velocity) (reason "6 transfers in 10m"))))))
     (submitted_at "2026-10-13 09:01:00Z") (status Pending) (notes ()))
    |}];
  (* Notes are still allowed after the decision; a second decision is not. *)
  let q = ok_exn (Review_queue.annotate q a ~author:"op-2" ~text:"checked" ~at:(at 4)) in
  print_s
    [%sexp
      (Review_queue.decide q a ~verdict:Reject ~operator:"op-2" ~at:(at 5)
       |> Or_error.is_ok
       : bool)];
  [%expect {| false |}];
  ignore (b : Review_queue.Item_id.t)
;;

let%expect_test "refusals" =
  let print r = print_s [%sexp (Or_error.map r ~f:(fun _ -> ()) : unit Or_error.t)] in
  print
    (Review_queue.submit
       Review_queue.empty
       ~reference:"tr-1"
       ~customer:"c"
       ~decision:Decision.allow
       ~at:(at 0));
  let q, id =
    ok_exn
      (Review_queue.submit
         Review_queue.empty
         ~reference:"tr-1"
         ~customer:"c"
         ~decision:review
         ~at:(at 0))
  in
  print
    (Review_queue.submit q ~reference:"tr-1" ~customer:"c" ~decision:review ~at:(at 1));
  print (Review_queue.annotate q id ~author:"op" ~text:"  " ~at:(at 1));
  print
    (Review_queue.decide
       q
       (Review_queue.Item_id.of_string "99")
       ~verdict:Approve
       ~operator:"op"
       ~at:(at 1));
  (* Once decided, the same reference may be held again (e.g. a retry). *)
  let q = ok_exn (Review_queue.decide q id ~verdict:Reject ~operator:"op" ~at:(at 2)) in
  print
    (Review_queue.submit q ~reference:"tr-1" ~customer:"c" ~decision:review ~at:(at 3));
  [%expect
    {|
    (Error ("review queue: nothing to review" tr-1))
    (Error ("review queue: already pending" tr-1))
    (Error "review queue: empty note")
    (Error ("review queue: unknown item" (id 99)))
    (Ok ())
    |}]
;;

let%expect_test "stable round trip and digest" =
  let q, _ =
    ok_exn
      (Review_queue.submit
         Review_queue.empty
         ~reference:"tr-1"
         ~customer:"c"
         ~decision:review
         ~at:(at 0))
  in
  let bin = Binable.to_string (module Review_queue.Stable.V1) q in
  assert (Review_queue.equal q (Binable.of_string (module Review_queue.Stable.V1) bin));
  assert (Review_queue.equal q (Review_queue.t_of_sexp (Review_queue.sexp_of_t q)));
  print_endline [%bin_digest: Review_queue.Stable.V1.t];
  print_endline [%bin_digest: Review_queue.Item.Stable.V1.t];
  [%expect
    {|
    85d95697cfb3e18148afd89c2bdfa430
    8047634937a866330f85f4df96aad2d5
    |}]
;;
