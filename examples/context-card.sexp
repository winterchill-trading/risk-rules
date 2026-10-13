;; An online card payment at a betting merchant with online payments switched off.
((customer cust-1) (tier verified) (now "2026-10-13 12:00:00Z")
 (balances ("250.00 EUR"))
 (subject
  (Card_auth
   ((id auth-1) (amount "40.00 EUR") (mcc 7995) (merchant_country (MT))
    (channel Online) (online_enabled false))))
 (history ()) (incoming ()) (card_history ())
 (geo ((ip_country (DE)) (residence (DE))))
 (session ((new_device false) (credentials_changed_at ()) (account_opened_at ())
   (failed_sca_24h 0))))
