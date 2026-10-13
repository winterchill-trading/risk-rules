open! Core

module Item_id = struct
  module Stable = struct
    module V1 = struct
      type t = int [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end

  include (Int : Identifiable.S with type t = int)

  let to_int t = t
end

module Verdict = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Approve
        | Reject
      [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end

  type t = Stable.V1.t =
    | Approve
    | Reject
  [@@deriving sexp, compare, equal, hash, enumerate]
end

module Note = struct
  module Stable = struct
    module V1 = struct
      type t =
        { author : string
        ; at : Time_ns.Stable.Alternate_sexp.V1.t
        ; text : string
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { author : string
    ; at : Time_ns.Alternate_sexp.t
    ; text : string
    }
  [@@deriving sexp, compare, equal]
end

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Pending
        | Decided of
            { verdict : Verdict.Stable.V1.t
            ; operator : string
            ; at : Time_ns.Stable.Alternate_sexp.V1.t
            }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    | Pending
    | Decided of
        { verdict : Verdict.t
        ; operator : string
        ; at : Time_ns.Alternate_sexp.t
        }
  [@@deriving sexp, compare, equal]
end

module Item = struct
  module Stable = struct
    module V1 = struct
      type t =
        { id : Item_id.Stable.V1.t
        ; reference : string
        ; customer : string
        ; decision : Decision.Stable.V1.t
        ; submitted_at : Time_ns.Stable.Alternate_sexp.V1.t
        ; status : Status.Stable.V1.t
        ; notes : Note.Stable.V1.t list
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { id : Item_id.t
    ; reference : string
    ; customer : string
    ; decision : Decision.t
    ; submitted_at : Time_ns.Alternate_sexp.t
    ; status : Status.t
    ; notes : Note.t list
    }
  [@@deriving sexp, compare, equal]

  let is_pending t =
    match t.status with
    | Pending -> true
    | Decided _ -> false
  ;;
end

module Stable = struct
  module V1 = struct
    (* Items are keyed by id; ids are allocated in submission order, so map order is FIFO
       order. *)
    type t =
      { next_id : int
      ; items : Item.Stable.V1.t Int.Map.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t =
  { next_id : int
  ; items : Item.t Int.Map.t
  }
[@@deriving sexp, compare, equal]

let empty = { next_id = 1; items = Int.Map.empty }
let items t = Map.data t.items
let find t id = Map.find t.items id
let pending t = List.filter (items t) ~f:Item.is_pending

let find_by_reference t reference =
  List.filter (items t) ~f:(fun item -> String.equal item.reference reference)
;;

let submit t ~reference ~customer ~(decision : Decision.t) ~at =
  match decision.severity with
  | Allow -> Or_error.error_s [%message "review queue: nothing to review" reference]
  | Review | Block ->
    if List.exists (find_by_reference t reference) ~f:Item.is_pending
    then Or_error.error_s [%message "review queue: already pending" reference]
    else (
      let id = t.next_id in
      let item =
        { Item.id
        ; reference
        ; customer
        ; decision
        ; submitted_at = at
        ; status = Pending
        ; notes = []
        }
      in
      Ok ({ next_id = id + 1; items = Map.set t.items ~key:id ~data:item }, id))
;;

let update t id ~f =
  match Map.find t.items id with
  | None -> Or_error.error_s [%message "review queue: unknown item" (id : int)]
  | Some item ->
    let%map.Or_error item = f item in
    { t with items = Map.set t.items ~key:id ~data:item }
;;

let decide t id ~verdict ~operator ~at =
  update t id ~f:(fun item ->
    match item.status with
    | Decided _ ->
      Or_error.error_s
        [%message "review queue: already decided" (id : int) (item.status : Status.t)]
    | Pending -> Ok { item with status = Decided { verdict; operator; at } })
;;

let annotate t id ~author ~text ~at =
  if String.is_empty (String.strip text)
  then Or_error.error_string "review queue: empty note"
  else
    update t id ~f:(fun item ->
      Ok { item with notes = item.notes @ [ { Note.author; at; text } ] })
;;
