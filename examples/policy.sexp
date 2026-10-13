;; Example risk policy. Amounts are "<decimal> <currency>" with the
;; currency's full number of fractional digits. A currency missing from a
;; cap's list is capped at zero.
((all_tiers
  ((Blocked_countries (KP IR SY CU))
   (High_risk_countries (AF MM PA))
   (Velocity (max_count 10) (window 10m))
   (New_beneficiary_cooldown
    (cooldown 24h)
    (above ("250.00 EUR" "0.00500000 BTC" "100.000000 USDC")))
   (Structuring
    (threshold ("10000.00 EUR"))
    (round_unit ("1000.00 EUR"))
    (min_count 3)
    (window 3d))
   (Unverified_self_hosted_wallet (above ("0.00100000 BTC" "1000.000000 USDC")))
   (Blocked_mccs (7995 6051))
   Online_toggle))
 (tiers
  ((basic
    ((Per_transfer_cap ("1000.00 EUR" "0.01000000 BTC" "1000.000000 USDC"))
     (Daily_cap ("2000.00 EUR" "0.02000000 BTC" "2000.000000 USDC"))
     (Monthly_cap ("10000.00 EUR" "0.10000000 BTC" "10000.000000 USDC"))))
   (verified
    ((Per_transfer_cap ("15000.00 EUR" "0.50000000 BTC" "15000.000000 USDC"))
     (Daily_cap ("25000.00 EUR" "1.00000000 BTC" "25000.000000 USDC"))
     (Monthly_cap ("100000.00 EUR" "5.00000000 BTC" "100000.000000 USDC"))))
   (under_review
    ((Manual_review (reason "customer under investigation")))))))
