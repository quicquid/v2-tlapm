(* Copyright (C) 2014 MSR-INRIA
 * Author: TL
*)
open Format

(**
   Tlapm datatypes are constructed in layers,
   where each layer is obtained from a previous one
   by the use of a transformation.
   The first layer is obtained from SANY and the last one
   contains the obligations shipped to the backends.

   This file contains common definitions shared by all layers.
*)

type int_range = {
  rbegin  : int;
  rend    : int
}

type location = {
  column  : int_range;
  line    : int_range;
  filename: string
}

type level =
  | ConstantLevel
  | StateLevel
  | TransitionLevel
  | TemporalLevel

type op_decl_kind =
  | ConstantDecl
  | VariableDecl
  | BoundSymbol
  | NewConstant
  | NewVariable
  | NewState
  | NewAction
  | NewTemporal

type prover =
  | Isabelle
  | Zenon
  | SMT
  | LS4
  | Tlaps
  | Nunchaku
  | Default

(** Creates a range from 0 to 0. *)
val mkDummyRange : int_range

(** Creates a location at line 0 to 0, column 0 to 0. *)
val mkDummyLocation : location

val toplevel_loation : location
(** Location for the toplevel *)

val format_location : location -> string
val fmt_location : formatter -> location -> unit

val fmt_location  : formatter -> location -> unit
val fmt_int_range : formatter -> int_range -> unit

val format_prover : prover -> string

val fmt_prover : formatter -> prover -> unit

val format_op_decl_kind : op_decl_kind -> string

val lmax : level -> level -> level

val level_of_op_decl_kind : op_decl_kind -> (level, string) Result.result
