(** Operations held for an operator.

    An immutable value: every change returns a new queue, so callers can journal the
    operations and rebuild the queue by replaying them. Items are never removed; a decided
    item stays for the audit trail. *)

open! Core

module Item_id : sig
  module Stable : sig
    module V1 : sig
      type t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end

  type t = Stable.V1.t

  include Identifiable.S with type t := t

  val to_int : t -> int
end

module Verdict : sig
  module Stable : sig
    module V1 : sig
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

module Note : sig
  module Stable : sig
    module V1 : sig
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
    ; at : Time_ns.t
    ; text : string
    }
  [@@deriving sexp, compare, equal]
end

module Status : sig
  module Stable : sig
    module V1 : sig
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
        ; at : Time_ns.t
        }
  [@@deriving sexp, compare, equal]
end

module Item : sig
  module Stable : sig
    module V1 : sig
      type t =
        { id : Item_id.Stable.V1.t
        ; reference : string (** the held operation, e.g. a transfer id *)
        ; customer : string
        ; decision : Decision.Stable.V1.t
        ; submitted_at : Time_ns.Stable.Alternate_sexp.V1.t
        ; status : Status.Stable.V1.t
        ; notes : Note.Stable.V1.t list (** oldest first *)
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { id : Item_id.t
    ; reference : string
    ; customer : string
    ; decision : Decision.t
    ; submitted_at : Time_ns.t
    ; status : Status.t
    ; notes : Note.t list
    }
  [@@deriving sexp, compare, equal]

  val is_pending : t -> bool
end

module Stable : sig
  module V1 : sig
    type t [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t [@@deriving sexp, compare, equal]

val empty : t

(** Hold an operation. Only [Review] and [Block] decisions are accepted ([Block] items are
    kept so an operator can confirm or overturn them); an [Allow] decision has nothing to
    review. A reference already in the queue and still pending is refused, so retries do
    not create duplicates. *)
val submit
  :  t
  -> reference:string
  -> customer:string
  -> decision:Decision.t
  -> at:Time_ns.t
  -> (t * Item_id.t) Or_error.t

(** Close a pending item. Fails if the item is unknown or already decided. *)
val decide
  :  t
  -> Item_id.t
  -> verdict:Verdict.t
  -> operator:string
  -> at:Time_ns.t
  -> t Or_error.t

(** Add a note to an item, pending or decided. Empty text is refused. *)
val annotate
  :  t
  -> Item_id.t
  -> author:string
  -> text:string
  -> at:Time_ns.t
  -> t Or_error.t

val find : t -> Item_id.t -> Item.t option
val find_by_reference : t -> string -> Item.t list

(** Pending items in submission order (FIFO). *)
val pending : t -> Item.t list

(** Every item, oldest first. *)
val items : t -> Item.t list
