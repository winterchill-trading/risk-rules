open! Core
open Risk_rules
open Fixtures

let%expect_test "per-transfer cap" =
  let rule = Rules.per_transfer_cap (limits [ eur "1000.00" ]) in
  check rule (context (transfer (eur "1000.00")));
  check rule (context (transfer (eur "1000.01")));
  (* BTC is not listed: limit zero, fail closed. *)
  check rule (context (transfer (btc "0.00000001")));
  (* Card authorisations are not transfers. *)
  check rule (context (card (eur "5000.00")));
  [%expect
    {|
    -
    block: 1000.01 EUR exceeds the per-transfer cap of 1000.00 EUR
    block: 0.00000001 BTC exceeds the per-transfer cap of 0.00000000 BTC (no limit configured for BTC)
    -
    |}]
;;

let%expect_test "daily cap counts the last 24 hours in the same currency" =
  let rule = Rules.daily_cap (limits [ eur "2000.00"; btc "0.10000000" ]) in
  let history =
    [ past (hours 2) (eur "900.00")
    ; past (hours 23) (eur "600.00")
    ; past (hours 25) (eur "5000.00") (* outside the window *)
    ; past (hours 1) (btc "1.00000000") (* other currency *)
    ]
  in
  check rule (context ~history (transfer (eur "500.00")));
  check rule (context ~history (transfer (eur "500.01")));
  [%expect
    {|
    -
    block: 500.01 EUR plus 1500.00 EUR already sent in 1d exceeds the cap of 2000.00 EUR
    |}]
;;

let%expect_test "monthly cap and future-dated history" =
  let rule = Rules.monthly_cap (limits [ eur "10000.00" ]) in
  let history =
    [ past (hours (24 * 29)) (eur "9000.00")
    ; past (hours (24 * 31)) (eur "9000.00")
    ; (* Clock skew: a record stamped after [now] is not counted. *)
      { (past (hours 0) (eur "9000.00")) with at = Time_ns.add t0 (minutes 5) }
    ]
  in
  check rule (context ~history (transfer (eur "1000.00")));
  check rule (context ~history (transfer (eur "1000.01")));
  [%expect
    {|
    -
    block: 1000.01 EUR plus 9000.00 EUR already sent in 30d exceeds the cap of 10000.00 EUR
    |}]
;;

let%expect_test "velocity" =
  let rule = Rules.velocity ~max_count:3 ~window:(minutes 10) () in
  let history n = List.init n ~f:(fun i -> past (minutes (i + 1)) (eur "1.00")) in
  check rule (context ~history:(history 2) (transfer (eur "1.00")));
  check rule (context ~history:(history 3) (transfer (eur "1.00")));
  check
    rule
    (context
       ~history:(past (minutes 11) (eur "1.00") :: history 2)
       (transfer (eur "1.00")));
  [%expect {|
    -
    review: 4 transfers in 10m (at most 3)
    -
    |}]
;;
