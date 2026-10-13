open! Core
open Risk_rules
open Fixtures

let%expect_test "new beneficiary cooldown" =
  let rule =
    Rules.new_beneficiary_cooldown
      ~cooldown:(hours 24)
      ~above:(limits [ eur "250.00" ])
      ()
  in
  let fresh = beneficiary ~first_seen:(ago (hours 3)) () in
  check rule (context (transfer ~beneficiary:fresh (eur "250.00")));
  check rule (context (transfer ~beneficiary:fresh (eur "250.01")));
  (* Past the cooldown. *)
  check
    rule
    (context
       (transfer
          ~beneficiary:(beneficiary ~first_seen:(ago (hours 25)) ())
          (eur "9000.00")));
  [%expect
    {|
    -
    block: 250.01 EUR to beneficiary ben-1 first seen 3h ago; above 250.00 EUR during the 1d cooldown
    -
    |}];
  (* Trusted beneficiaries are only exempt when the policy says so. *)
  let exempt =
    Rules.new_beneficiary_cooldown
      ~exempt_trusted:true
      ~cooldown:(hours 24)
      ~above:(limits [ eur "250.00" ])
      ()
  in
  check exempt (context (transfer ~beneficiary:fresh (eur "900.00")));
  check
    exempt
    (context (transfer ~beneficiary:{ fresh with trusted = false } (eur "900.00")));
  [%expect
    {|
    -
    block: 900.00 EUR to beneficiary ben-1 first seen 3h ago; above 250.00 EUR during the 1d cooldown
    |}]
;;

let%expect_test "structuring: round amounts and amounts just below a threshold" =
  let rule =
    Rules.structuring
      ~threshold:(limits [ eur "10000.00" ])
      ~round_unit:(limits [ eur "1000.00" ])
      ~min_count:3
      ~window:(hours 72)
      ()
  in
  let history =
    [ past (hours 10) (eur "9800.00") (* within 10% below the threshold *)
    ; past (hours 30) (eur "3000.00") (* round *)
    ; past (hours 40) (eur "1234.56") (* neither *)
    ; past (hours 100) (eur "9900.00") (* outside the window *)
    ]
  in
  check rule (context ~history (transfer (eur "5000.00")));
  check rule (context ~history (transfer (eur "9500.00")));
  (* The current transfer must itself look structured. *)
  check rule (context ~history (transfer (eur "4321.00")));
  (* 9000.01 is within the margin, but 8999.99 sits just outside it, so this is one match
     out of the three needed. *)
  check
    rule
    (context ~history:[ past (hours 1) (eur "8999.99") ] (transfer (eur "9000.01")));
  (* A currency without settings never matches. *)
  check
    rule
    (context
       ~history:[ past (hours 1) (btc "1.00000000"); past (hours 2) (btc "1.00000000") ]
       (transfer (btc "1.00000000")));
  [%expect
    {|
    review: 3 round or just-below-threshold transfers in 3d (this one 5000.00 EUR)
    review: 3 round or just-below-threshold transfers in 3d (this one 9500.00 EUR)
    -
    -
    -
    |}]
;;

let%expect_test "countries" =
  let blocked = Rules.blocked_countries [ country "KP"; country "IR" ] in
  let risky = Rules.high_risk_countries [ country "PA"; country "AE" ] in
  let geo =
    { Context.Geo.ip_country = Some (country "AE"); residence = Some (country "DE") }
  in
  let to_country c =
    transfer ~beneficiary:(beneficiary ~country:(country c) ()) (eur "10.00")
  in
  check blocked (context (to_country "KP"));
  check risky (context (to_country "KP"));
  check risky (context ~geo (to_country "PA"));
  check risky (context ~geo (to_country "DE"));
  (* Card merchant countries count too. *)
  check blocked (context (card ~merchant_country:(country "IR") (eur "10.00")));
  check blocked (context (to_country "DE"));
  [%expect
    {|
    block: blocked country: KP
    -
    review: high-risk country: PA, AE
    review: high-risk country: AE
    block: blocked country: IR
    -
    |}]
;;
