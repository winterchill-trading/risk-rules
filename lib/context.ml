open! Core

module Wallet = struct
  type t =
    { self_hosted : bool
    ; ownership_verified : bool
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Transfer = struct
  type t =
    { draft : Payments_core.Transfer.Stable.V1.t
    ; beneficiary : Payments_core.Beneficiary.Stable.V1.t
    ; beneficiary_country : Country.t option
    ; wallet : Wallet.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  let default_country (beneficiary : Payments_core.Beneficiary.t) =
    match beneficiary.destination with
    | Bank_account { iban; bic = _ } ->
      Country.of_string_or_error (Payments_core.Iban.country iban) |> Result.ok
    | Uk_account _ -> Some (Country.of_string "GB")
    | Us_account _ -> Some (Country.of_string "US")
    (* Local scheme names start with the market's country code ([kg], [ch_qr_iban]). *)
    | Local { scheme; fields = _ } ->
      let prefix =
        Option.value_map (String.lsplit2 scheme ~on:'_') ~default:scheme ~f:fst
      in
      if String.length prefix = 2
      then Country.of_string_or_error (String.uppercase prefix) |> Result.ok
      else None
    | Crypto _ | Lightning _ | Internal _ -> None
  ;;

  let wallet_of_details : Payments_core.Transfer.Details.t -> Wallet.t option = function
    | Onchain { travel_rule = Some { counterparty_wallet = Hosted _; _ }; _ } ->
      Some { self_hosted = false; ownership_verified = false }
    | Onchain
        { travel_rule =
            Some { counterparty_wallet = Self_hosted { ownership_verified }; _ }
        ; _
        } -> Some { self_hosted = true; ownership_verified }
    | Onchain { travel_rule = None; _ }
    | Sepa _ | Lightning _ | Intraledger | Card | Uk_domestic _ | Us_domestic _ -> None
  ;;

  let create ?country ?wallet (draft : Payments_core.Transfer.t) =
    let wallet =
      match wallet with
      | Some _ -> wallet
      | None -> wallet_of_details draft.details
    in
    match draft.direction, draft.counterparty with
    | Out, Beneficiary beneficiary ->
      let beneficiary_country =
        match country with
        | Some _ -> country
        | None -> default_country beneficiary
      in
      Ok { draft; beneficiary; beneficiary_country; wallet }
    | In, _ | Out, External _ ->
      Or_error.error_s
        [%message
          "context: expected an outgoing transfer to a beneficiary"
            ~transfer:(draft.id : Payments_core.Transfer.Id.t)]
  ;;

  let amount t = t.draft.amount
end

module Past_transfer = struct
  type t =
    { at : Time_ns.Alternate_sexp.t
    ; amount : Money.Amount.Stable.V1.t
    ; beneficiary : Payments_core.Beneficiary.Id.Stable.V1.t option
    ; sender : string option
    }
  [@@deriving bin_io, sexp, compare, equal]

  let of_transfer (transfer : Payments_core.Transfer.t) =
    (* Transfers still waiting for strong authentication count: otherwise a customer could
       queue many unconfirmed transfers that each pass the cap alone and confirm them
       together. *)
    (* Matched by constructor name: payments-core is still growing its status set
       (rejections, recalls), and a name list keeps this summary compiling across those
       additions. A recall that is requested or refused still has the money out of the
       account, so it counts. *)
    let counts =
      List.mem
        [ "Awaiting_sca"
        ; "Submitted"
        ; "Pending"
        ; "Settled"
        ; "Recall_requested"
        ; "Recall_refused"
        ]
        (Payments_core.Transfer.Status.name transfer.status)
        ~equal:String.equal
    in
    match transfer.direction, counts, List.last transfer.history with
    | Out, true, Some (_, at) ->
      let beneficiary =
        match transfer.counterparty with
        | Beneficiary b -> Some b.id
        | External _ -> None
      in
      Some { at; amount = transfer.amount; beneficiary; sender = None }
    | (In | Out), _, _ -> None
  ;;

  let of_incoming ?(sender_key = Fn.id) (transfer : Payments_core.Transfer.t) =
    let arrived =
      List.mem
        [ "Pending"; "Settled" ]
        (Payments_core.Transfer.Status.name transfer.status)
        ~equal:String.equal
    in
    match transfer.direction, arrived, List.last transfer.history with
    | In, true, Some (_, at) ->
      let sender =
        match transfer.counterparty with
        | External { detail; name = _ } -> Some (sender_key detail)
        | Beneficiary _ -> None
      in
      Some { at; amount = transfer.amount; beneficiary = None; sender }
    | (In | Out), _, _ -> None
  ;;
end

module Card_auth = struct
  module Channel = struct
    type t =
      | In_person
      | Online
      | Atm
    [@@deriving bin_io, sexp, compare, equal, enumerate]
  end

  type t =
    { id : string
    ; amount : Money.Amount.Stable.V1.t
    ; mcc : Mcc.Stable.V1.t
    ; merchant_country : Country.t option
    ; channel : Channel.t
    ; online_enabled : bool
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Past_auth = struct
  type t =
    { at : Time_ns.Alternate_sexp.t
    ; amount : Money.Amount.Stable.V1.t
    ; merchant : string
    ; approved : bool
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Geo = struct
  type t =
    { ip_country : Country.t option
    ; residence : Country.t option
    }
  [@@deriving bin_io, sexp, compare, equal]

  let unknown = { ip_country = None; residence = None }
end

module Session = struct
  type t =
    { new_device : bool
    ; credentials_changed_at : Time_ns.Alternate_sexp.t option
    ; account_opened_at : Time_ns.Alternate_sexp.t option
    ; failed_sca_24h : int
    }
  [@@deriving bin_io, sexp, compare, equal]

  let unknown =
    { new_device = false
    ; credentials_changed_at = None
    ; account_opened_at = None
    ; failed_sca_24h = 0
    }
  ;;
end

module Subject = struct
  type t =
    | Transfer of Transfer.t
    | Card_auth of Card_auth.t
  [@@deriving bin_io, sexp, compare, equal]
end

type t =
  { customer : string
  ; tier : Tier.Stable.V1.t
  ; now : Time_ns.Alternate_sexp.t
  ; balances : Money.Amount.Stable.V1.t list
  ; subject : Subject.t
  ; history : Past_transfer.t list
  ; incoming : Past_transfer.t list
  ; card_history : Past_auth.t list
  ; geo : Geo.t
  ; session : Session.t
  }
[@@deriving bin_io, sexp, compare, equal]

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end

let amount t =
  match t.subject with
  | Transfer transfer -> Transfer.amount transfer
  | Card_auth auth -> auth.amount
;;

let transfer t =
  match t.subject with
  | Transfer transfer -> Some transfer
  | Card_auth _ -> None
;;

let card_auth t =
  match t.subject with
  | Card_auth auth -> Some auth
  | Transfer _ -> None
;;

let balance t currency =
  List.find t.balances ~f:(fun amount ->
    Money.Currency.equal (Money.Amount.currency amount) currency)
;;

let within t ~window list =
  let since = Time_ns.sub t.now window in
  List.filter list ~f:(fun (past : Past_transfer.t) ->
    Time_ns.( > ) past.at since && Time_ns.( <= ) past.at t.now)
;;

let history_within t ~window = within t ~window t.history

let card_history_within t ~window =
  let since = Time_ns.sub t.now window in
  List.filter t.card_history ~f:(fun (auth : Past_auth.t) ->
    Time_ns.( > ) auth.at since && Time_ns.( <= ) auth.at t.now)
;;

let incoming_within t ~window = within t ~window t.incoming

let countries t =
  let counterparty =
    match t.subject with
    | Transfer transfer -> transfer.beneficiary_country
    | Card_auth auth -> auth.merchant_country
  in
  List.stable_dedup
    (List.filter_opt [ counterparty; t.geo.ip_country ])
    ~compare:Country.compare
;;
