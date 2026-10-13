open! Core

type t = Money.Amount.t list [@@deriving compare, equal, sexp_of]

let create amounts =
  let currencies = List.map amounts ~f:Money.Amount.currency in
  match List.find_a_dup currencies ~compare:Money.Currency.compare with
  | Some currency ->
    Or_error.error_s
      [%message "limits: currency listed twice" (currency : Money.Currency.t)]
  | None ->
    (match List.find amounts ~f:Money.Amount.is_negative with
     | Some amount ->
       Or_error.error_s [%message "limits: negative limit" (amount : Money.Amount.t)]
     | None -> Ok amounts)
;;

let create_exn amounts = Or_error.ok_exn (create amounts)
let t_of_sexp sexp = create_exn ([%of_sexp: Money.Amount.t list] sexp)
let to_list t = t

let find t currency =
  match
    List.find t ~f:(fun amount ->
      Money.Currency.equal (Money.Amount.currency amount) currency)
  with
  | Some limit -> `Configured limit
  | None -> `Missing (Money.Amount.zero currency)
;;

let limit_for t currency =
  match find t currency with
  | `Configured limit -> limit, ""
  | `Missing zero ->
    zero, sprintf " (no limit configured for %s)" (Money.Currency.to_string currency)
;;
