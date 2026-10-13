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
      (amount "750.00 EUR") (fee "0.00 EUR") (reference "")
      (details
       (Sepa
        ((payment_id
          ((end_to_end_id E2E-1) (instruction_id ()) (uetr ()) (tx_id ())
           (msg_id ()) (pmt_inf_id ())))
         (debtor
          ((name "Customer One") (iban DE77100100100123456789) (bic ())
           (address ())))
         (creditor
          ((name "Test Payee") (iban DE89370400440532013000) (bic ())
           (address ())))
         (remittance (Unstructured test)) (charge_bearer SLEV) (purpose ())
         (requested_execution_date ()) (acceptance_time ()) (value_date ())
         (booking_date ()) (last_status ()))))
      (status Draft) (history ((Draft "2026-10-13 12:00:00Z"))) (authorization ())
      (provider_ref ())))
    (beneficiary
     ((id ben-1) (owner cust-1) (name "Test Payee")
      (destination (Bank_account (iban DE89370400440532013000) (bic ())))
      (trusted false) (first_seen "2026-10-13 10:00:00Z") (payee_check ())))
    (beneficiary_country (DE)) (wallet ()))))
 (history
  (((at "2026-10-13 09:00:00Z") (amount "900.00 EUR") (beneficiary (ben-1)) (sender ()))
   ((at "2026-10-12 06:00:00Z") (amount "200.00 EUR") (beneficiary (ben-1)) (sender ()))))
 (incoming ()) (card_history ()) (geo ((ip_country (DE)) (residence (DE))))
 (session
  ((new_device false) (credentials_changed_at ()) (account_opened_at ())
   (failed_sca_24h 0))))
