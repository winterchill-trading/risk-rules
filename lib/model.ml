open! Core

module Score = struct
  type t =
    { value : float
    ; reasons : (string * float) list
    }
  [@@deriving sexp_of, compare, equal]

  let create ~value ~reasons =
    if Float.is_nan value || Float.( < ) value 0. || Float.( > ) value 1.
    then Or_error.error_s [%message "model score outside [0, 1]" (value : float)]
    else (
      match List.find reasons ~f:(fun (_, c) -> not (Float.is_finite c)) with
      | Some (code, contribution) ->
        Or_error.error_s
          [%message
            "model reason with a non-finite contribution" code (contribution : float)]
      | None ->
        Ok
          { value
          ; reasons =
              List.stable_sort reasons ~compare:(fun (_, a) (_, b) -> Float.compare b a)
          })
  ;;
end

module type S = sig
  val name : string
  val version : string
  val score : Features.t -> Score.t
end

type t = (module S)

let name (module M : S) = M.name
let version (module M : S) = M.version
let score (module M : S) features = M.score features

let constant ~name value : t =
  let score = Or_error.ok_exn (Score.create ~value ~reasons:[]) in
  (module struct
    let name = name
    let version = "constant"
    let score _ = score
  end)
;;

let sigmoid x = 1. /. (1. +. Float.exp (-.x))

let logistic ~name ~version ~intercept ~weights ?(top = 3) () =
  match
    List.find weights ~f:(fun (feature, _) ->
      not (List.mem Features.numeric_names feature ~equal:String.equal))
  with
  | Some (feature, _) ->
    Or_error.error_s [%message "logistic model: unknown feature" feature]
  | None ->
    let weights = String.Map.of_alist_reduce weights ~f:( +. ) in
    let score features =
      let contributions =
        List.filter_map (Features.to_floats features) ~f:(fun (feature, x) ->
          match Map.find weights feature with
          | Some w when not (Float.is_nan x) -> Some (feature, w *. x)
          | Some _ | None -> None)
      in
      let z = List.fold contributions ~init:intercept ~f:(fun acc (_, c) -> acc +. c) in
      let reasons =
        List.filter contributions ~f:(fun (_, c) -> Float.is_finite c && Float.( > ) c 0.)
        |> List.sort ~compare:(fun (_, a) (_, b) -> Float.compare b a)
        |> fun l -> List.take l top
      in
      (* A huge feature value (an amount in the millions) can overflow the sum; clamp so
         the score stays a valid probability. *)
      let value =
        if Float.is_nan z then 1. else Float.clamp_exn (sigmoid z) ~min:0. ~max:1.
      in
      Or_error.ok_exn (Score.create ~value ~reasons)
    in
    Ok
      (module struct
        let name = name
        let version = version
        let score = score
      end : S)
;;
