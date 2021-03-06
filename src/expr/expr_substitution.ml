open Any_expr
open List
open Util
open Expr_ds
open Expr_map
open Expr_utils
open Expr_dereference
open Expr_termdb_utils
open Expr_termdb_utils.DeepTraversal
open Expr_formatter
open Format

let debug f = () (* ignore(f ()) *)

(* TODO: check if this is really the equality we want (including location) *)
let compare_modulo_deref_formal_param term_db f1 f2 =
  match f1, f2 with
  | FP_ref i, FP_ref j when i = j -> true
  | _,_ (* when i <> j *) ->
    match Deref.formal_param term_db f1 with
    | {id; location; level; name; arity } ->
      let fp = Deref.formal_param term_db f2 in
      (location = fp.location) && (level = fp.level)
      && (name = fp.name) && (arity = fp.arity)

module Subst =
struct
  (** substitution of formal parameter by an expression *)
  type subst = Expr_ds.fp_assignment
  type substs = subst list


  let domain = map (function | {param; expr} -> param)
  let range tdb =
    (* TODO: fix EO case and type of this function, it must return formal_param list *)
    flat_map (function
        | {param; expr = EO_expr e;} -> free_variables tdb e
        | _ -> [] )

  let formal_params_in_range tdb =
    flat_map (function
        | {param; expr} ->
          let acc = DTAcc (tdb, IntSet.empty, FP_Set.empty) in
          let v= new formal_param_visitor in
          let set = v#expr_or_op_arg acc expr |> v#dtacc_inner_acc in
          FP_Set.elements set
      )

  let rec rename term_db ?free:(free=[]) ?bound:(bound=[]) ?defs:(defs=[]) =
    function
    | (FP_ref x) as fp ->
      match Deref.formal_param term_db fp with
      | { id; location; level; name; arity; } ->
        let free_names =
          fold_left (fun x y ->
              let opdeci = Deref.op_decl term_db y in
              StringSet.add opdeci.name x
            ) StringSet.empty free
        in
        let fbound_names =
          fold_left (fun x y ->
              let fpi = Deref.formal_param term_db y in
              StringSet.add fpi.name x
            ) free_names bound
        in
        let fbdef_names =
          fold_left
            (fun x ->
               function
               | O_module_instance mi -> x
               | O_builtin_op op ->
                 let opi = Deref.builtin_op term_db op in
                 StringSet.add opi.name x
               | O_user_defined_op op ->
                 let opi = Deref.user_defined_op term_db op in
                 StringSet.add opi.name x
               | O_thm_def op ->
                 let opi = Deref.theorem_def term_db op in
                 StringSet.add opi.name x
               | O_assume_def op ->
                 let opi = Deref.assume_def term_db op in
                 StringSet.add opi.name x
            ) fbound_names defs
        in
        let find_name blacklist =
          let rec find_name_ blacklist n =
            let new_name = name ^ (string_of_int n) in
            if StringSet.mem new_name fbdef_names then
              find_name_ blacklist (n+1)
          else
            new_name
          in
          if StringSet.mem name blacklist then find_name_ blacklist 0 else name
        in
        debug (fun () ->
            fprintf std_formatter "@[Renaming blacklist %a@,@]"
              (StringSet.pp ~start:"[" ~stop:"]" ~sep:"; " CCFormat.string)
              fbdef_names);
        let fp_ = { id; location; level; name = find_name fbdef_names; arity } in
        debug (fun () ->
            fprintf std_formatter "@.mapped %s <- %s@." name fp_.name);
        mkref_formal_param term_db fp_

  (* removes formal params in fps from substition domain *)
  let remove_from_subst termdb fps =
    let remove_from_subst_ termdb fps =
      filter (function {param; expr} ->
          mem (Deref.formal_param termdb param) fps
        )
    in remove_from_subst_ termdb (map (Deref.formal_param termdb) fps)

  (* looks for mapping of fp in substs *)
  let find_subst ?cmp:(cmp=(=))  term_db fp =
    let dr = Deref.formal_param term_db in
    let cmpi x y = cmp (dr x) (dr y) in
    fold_left (function
        | None ->
          begin
            function
            | {param; expr; } when param = fp ->
              Some expr
            | {param; expr; } when cmpi param fp ->
              (* references are now unique, but cmp might give us something *)
              Some expr
            | _ -> None
          end
        | Some _ as x ->
          fun _ -> x
      ) None
end

(* substitution algorithm *)
type 'a subst_acc = {
  term_db : term_db;
  substs   : Subst.substs;
  bound_context : formal_param list;
  bound_renaming : (formal_param * formal_param) list;
  subclass_acc : 'a;
}

module SubFormat = struct
  let fmt_bound_context ?intro:(str="Bound context: ") term_db =
    fmt_list ~front:str (fmt_formal_param term_db)

  let fmt_subst term_db formatter = function
    | {param; expr; } ->
      fprintf formatter "%a <- %a;"
        (fmt_formal_param term_db) param
        (fmt_expr_or_op_arg term_db) expr


  let fmt_substs ?intro:(str="[") term_db formatter =
    fmt_list ~front:str (fmt_subst term_db) formatter

  let fmt_renaming ?intro:(str="[") term_db =
    fmt_list ~front:str
      (fun formatter ->
         function  | (x,y) ->
           fprintf formatter "%a <- %a;"
             (fmt_formal_param term_db) x
             (fmt_formal_param term_db) y
      )

  let fmt_sacc formatter
      { term_db; bound_context; bound_renaming; substs; _} =
    fprintf formatter "SAcc @[<v 2>@[{@,%a@,%a@,%a@,}@]@]"
      (fmt_substs term_db) substs
      (fmt_bound_context term_db) bound_context
      (fmt_renaming term_db) bound_renaming
    ;
    ()

  let fmt_formal_param_ref term_db formatter = function
    | FP_ref id -> fprintf formatter "%d" id

  let print_acc ?text:(text="acc:") sacc () =
    fprintf std_formatter "@[<v>%s@,%a@,@]" text fmt_sacc sacc
end

class ['a] expr_substitution = object(self)
  inherit ['a subst_acc] expr_map as super

  method expr acc = function
    (* formal param replaced by expression *)
    | E_op_appl { location; level;
                  operator = FMOTA_formal_param fp; operands = [] }  ->
      let sacc = get_acc acc in
      begin
        match Subst.find_subst sacc.term_db fp sacc.substs with
        | None ->
          let e = E_op_appl { location; level;
                              operator = FMOTA_formal_param fp;
                              operands = []; } in
          set_anyexpr acc (Any_expr e)
        | Some (EO_expr e) ->
          set_anyexpr acc (Any_expr e)
        | Some (EO_op_arg o) ->
          failwith "Tried to replace an expression by an operator."
      end
    (* formal param replaced by operator *)
    | E_op_appl opappl as e  ->
      super#expr acc e (* handled in self#operator *)
    | E_binder b as e -> super#expr acc e (* handled in self#binder *)
    | E_at x        as e -> super#expr acc e (* TODO: handle *)
    | E_label x     as e -> super#expr acc e (* TODO: handle *)
    | E_subst_in x  as e -> super#expr acc e (* TODO: handle *)
    (* can not contain formal parameters *)
    | E_decimal x   as e -> super#expr acc e
    | E_string x    as e -> super#expr acc e
    | E_numeral x   as e -> super#expr acc e
    | E_let_in x    as e -> super#expr acc e
    | E_fp_subst_in x as e ->  (* TODO: handle *)
      failwith "unhandled push of fp subst over explicit subst"

  method subst_in acc s =
    failwith "Expr substitution inside instantiation not supported."

  method ap_subst_in acc s =
    failwith "Assume Prove substitution inside instantiation not supported."

  method op_appl acc ({ location; level; operator; operands; } as appl) =
    super#op_appl acc appl

  method unbounded_bound_symbol acc { param; tuple } =
    let sacc = get_acc acc in
    let free = Subst.range sacc.term_db sacc.substs in
    let bound : formal_param list = concat
        [ (* [param]; *)
          (Subst.formal_params_in_range sacc.term_db sacc.substs);
          sacc.bound_context;
        ]
    in
    let (rterm_db, rparam) = Subst.rename sacc.term_db ~free ~bound param in
    let (bound_context, bound_renaming) =
      (rparam :: sacc.bound_context, (param, rparam) :: sacc.bound_renaming)
    in
    let acc0 = set_acc acc { term_db = rterm_db;
                             substs = sacc.substs;
                             bound_context;
                             bound_renaming;
                             subclass_acc = ();
                           } in
    let ubs = { param = rparam; tuple; } in
    set_anyexpr acc0 (Any_unbounded_bound_symbol ubs)

  method bounded_bound_symbol acc { params; tuple; domain } =
    (* recurse into domain first, SANY does not allow params
       in the domain *)
    let sacc = get_acc acc in
    (*
    let acc0  = self#expr acc domain in
    let sacc0 = get_acc acc0 in
    let domain = self#get_macc_extractor#expr acc in
     *)
    let bound = concat
        [ (* params; *)
          (Subst.formal_params_in_range sacc.term_db sacc.substs);
          sacc.bound_context;
        ]
    in
    let free = Subst.range sacc.term_db sacc.substs in
    (* do renaming of symbols, if neccessary *)
    let (rterm_db, rparams_reverse, _blacklist) =
      fold_left (function
          | (rdb, rps, bl) ->
            fun param ->
              let db, rp =
                Subst.rename rdb ~free ~bound:bl param
              in
              (db, rp::rps, rp::bl)
        )
        (sacc.term_db, [], bound) params
    in
    (* restore parameter order *)
    let rparams = rev rparams_reverse in
    assert(length params = length rparams); (* TODO: check if this holds *)
    (* create the renaming from old to new symbols *)
    let bound_renaming =
      filter (function
          | (fpo, fpn) ->
            not (compare_modulo_deref_formal_param rterm_db fpo fpn)
        )
        (combine params rparams)
    in
    debug (fun () ->
        fprintf std_formatter "@[<v>Params : %a @,Rparams: %a@,@]"
          (fmt_list (fmt_formal_param sacc.term_db)) params
          (fmt_list (fmt_formal_param rterm_db)) rparams
        ;
        fprintf std_formatter "@[<v>Mapping: %a (bounded)@,@]"
          (SubFormat.fmt_renaming rterm_db) bound_renaming
      );
    (* add new symbols to bound context *)
    let bound_context =  append bound rparams
    in
    let acc0 = set_acc acc { term_db = rterm_db;
                             substs = sacc.substs;
                             bound_context =
                               append sacc.bound_context bound_context;
                             bound_renaming =
                               append sacc.bound_renaming bound_renaming;
                             subclass_acc = ();
                           } in
    let acc1  = self#expr acc0 domain in
    let domain = self#get_macc_extractor#expr acc1 in
    let ubs = { params = rparams; tuple; domain } in
    set_anyexpr acc1 (Any_bounded_bound_symbol ubs)

  method operator acc = function
    | FMOTA_formal_param fp as op ->
      let sacc = get_acc acc in
      begin
        match Subst.find_subst sacc.term_db fp sacc.substs with
        | None ->
          set_anyexpr acc (Any_operator op)
        | Some (EO_op_arg { location; level; argument }) ->
          set_anyexpr acc (Any_operator argument)
        | Some (EO_expr e) ->
          failwith "Tried to replace an expression by an operator."
      end
    | FMOTA_op_decl op_decl         as op -> super#operator acc op
    | FMOTA_op_def op_def           as op -> super#operator acc op
    | FMOTA_ap_subst_in ap_subst_in as op -> super#operator acc op
    | FMOTA_lambda lambda           as op -> super#operator acc op

  method binder acc { location; level; operator; operand; bound_symbols } =
    let sacc = get_acc acc in
    debug
      (fun () -> fprintf std_formatter
          "Binder acc: @.%a@." SubFormat.fmt_sacc sacc) ;
    (* process bound symbols to get the renaming *)
    let ie = self#get_id_extractor in
    let bound_symbols, acc0 =
      unpack_fold ie#bound_symbol self#bound_symbol acc bound_symbols in
    (* apply renaming to operand, the operator is always a built-in and
          doesn't need to be processed *)
    let sacc0 = get_acc acc0 in
    debug (fun () ->
        fprintf std_formatter "After processing bound sybols:@.%a@."
          SubFormat.fmt_sacc sacc0)
    ;
    let renaming_substs =
      map (function (param,y) ->
          let argument = FMOTA_formal_param y in
          let expr = EO_op_arg { location; level; argument } in
          { param; expr; }
        )
        sacc0.bound_renaming
    in
    debug (fun () ->
        fprintf std_formatter "Bound vars #: %d (binder)@.Renamed #: %d (binder)@."
          (length bound_symbols) (length renaming_substs));
    let sacc1 = { substs = renaming_substs;
                  term_db = sacc0.term_db;
                  bound_context = sacc0.bound_context;
                  bound_renaming = sacc0.bound_renaming;
                  subclass_acc = ();
                } in
    let acc1 = set_acc acc0 sacc1  in
    debug (fun () ->
        fprintf std_formatter
          "Renaming acc: @.%a to %a@."
          SubFormat.fmt_sacc sacc1
          (fmt_expr_or_op_arg sacc1.term_db) operand)
    ;
    let any_renamed_operand, sacc2 = self#expr_or_op_arg acc1 operand in
    (* apply substitution to renamed operator *)
    (* TODO: the renaming assures that we don't need to remove the old
       bound variables from the substitution. Decide if we want to remove them
       anyway.

       Right now, we also do not rename if there is a collision with a
       formal parameter bound in one of the domains in bound_symbols.
    *)
    let sacc3 = { term_db = sacc2.term_db;
                  substs = sacc.substs;
                  bound_context = sacc2.bound_context;
                  bound_renaming = [];
                  subclass_acc = ();
                } in
    let acc3 = (any_renamed_operand, sacc3) in
    let any_substituted_operand, sacc4 =
      ie#expr_or_op_arg any_renamed_operand
      |> self#expr_or_op_arg acc3
    in
    (* create binder for return value *)
    let binder = { location; level; operator;
                   operand = ie#expr_or_op_arg any_substituted_operand;
                   bound_symbols }
    in
    (* create subst accumulator for passing up *)
    let bsacc = { term_db = sacc4.term_db;
                  substs = sacc.substs;
                  bound_context = sacc.bound_context;
                  bound_renaming = sacc.bound_renaming;
                  subclass_acc = ();
                } in
    (Any_binder binder, bsacc)

  method user_defined_op acc = function
    | UOP_ref uid as uop ->
      set_anyexpr acc (Any_user_defined_op uop)

  method user_defined_op_ acc uop =
      (* Don't recurse into the body, any substitution is applied
         to the arguments as soon as the operator is applied.
      *)
      set_anyexpr acc (Any_user_defined_op_ uop)

  method bound_symbol acc b =
    SubFormat.print_acc ~text:"Bound symbol before:" (get_acc acc) |> debug;
    let acc0 = super#bound_symbol acc b in
    SubFormat.print_acc ~text:"Bound symbol after:" (get_acc acc0) |> debug;
    acc0


  method context acc _ =
    failwith "Can't apply a substitution to a context."

end

let instance = new expr_substitution

let subst_expr term_db substs expr =
  instance#expr (Nothing, { term_db; substs;
                            bound_context = []; bound_renaming = [];
                            subclass_acc = ();
                          }) expr
  |> (function | (x, { term_db; _ }) ->
      (instance#get_id_extractor#expr x,term_db))

let subst_op term_db substs op =
  instance#operator (Nothing, { term_db; substs;
                                bound_context = []; bound_renaming = [];
                                subclass_acc = ();
                              }) op
  |> (function | (x, { term_db; _ }) ->
      (instance#get_id_extractor#operator x,term_db))
