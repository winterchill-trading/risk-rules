;; Example risk policy. Amounts are "<decimal> <currency>" with the
;; currency's full number of fractional digits. A currency missing from a
;; cap's list is capped at zero. Defaults follow the transaction monitoring
;; research note; tune them on data.
((all_tiers
  (;; Sanctions and geography
   (Blocked_countries (KP IR SY CU))
   (High_risk_countries (AF MM PA))
   ;; Velocity and structuring
   (Velocity (max_count 10) (window 10m))
   (Structuring
    (threshold ("10000.00 EUR"))
    (round_unit ("1000.00 EUR"))
    (margin_bps 500)
    (min_count 3)
    (window 7d))
   ;; Money mules
   (Mule_pass_through (window 1h) (min_incoming ("200.00 EUR")))
   (Mule_fan_in (min_senders 5) (window 1d) (max_account_age 30d))
   (New_account_payout (max_age 7d) (above ("500.00 EUR")))
   ;; Account takeover: all four signals at once is a block
   (New_beneficiary_cooldown
    (cooldown 24h)
    (above ("250.00 EUR" "0.00500000 BTC" "100.000000 USDC")))
   (Severity Block
    (Account_takeover (recent 24h) (min_signals 4) (balance_share_bps 9000)))
   ;; Authorised push payment scams
   (App_fraud (new_within 48h))
   (App_first_large_payment (new_within 48h))
   Vop_not_matched
   ;; Crypto
   (Unverified_self_hosted_wallet (above ("0.00100000 BTC" "1000.000000 USDC")))
   ;; Cards
   (Blocked_mccs (7995 6051))
   Online_toggle
   (Card_testing (small ("2.00 EUR")) (count 5) (window 10m))
   ;; Model score in shadow mode until two weeks of stable alert counts
   (Shadow
    (Score (model fraud-gbt)
     (thresholds ((challenge_at 0.5) (review_at 0.8) (block_at 0.97)))))
   ;; Strong customer authentication, with exemptions recorded as allow hits
   (Sca_tra (scheme Credit_transfer) (observed_fraud_rate_ppm 40))
   (Sca_tra (scheme Card_not_present) (observed_fraud_rate_ppm 500))))
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
