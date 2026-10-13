;; A basic-tier customer sending 750.00 EUR to a beneficiary added two hours ago.
((customer cust-1) (tier basic) (now "2026-10-13 12:00:00Z")
 (balances ("10000.00 EUR"))
 (subject
  (Transfer
   ((draft
     ((id tr-1) (direction Out) (rail Sepa_instant) (account customer:1/eur)
      (counterparty
       (Beneficiary
        ((id ben-1) (owner cust-1) (name "Test Payee")
         (destination (Bank_account (iban DE89370400440532013000) (bic ())))
         (trusted false) (first_seen "2026-10-13 10:00:00Z")
         (payee_check ()))))
      (amount "750.00 EUR") (fee "0.00 EUR") (reference "") (status Draft)
      (history ((Draft "2026-10-13 12:00:00Z"))) (sca ()) (provider_ref ())))
    (beneficiary
     ((id ben-1) (owner cust-1) (name "Test Payee")
      (destination (Bank_account (iban DE89370400440532013000) (bic ())))
      (trusted false) (first_seen "2026-10-13 10:00:00Z") (payee_check ())))
    (beneficiary_country (DE)) (wallet ()))))
 (history
  (((at "2026-10-13 09:00:00Z") (amount "900.00 EUR") (beneficiary (ben-1)))
   ((at "2026-10-12 06:00:00Z") (amount "200.00 EUR") (beneficiary (ben-1)))))
 (geo ((ip_country (DE)) (residence (DE)))))
