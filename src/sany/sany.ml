(* Copyright (C) 2014 MSR-INRIA
 * SANY Parsing
 * Author: TL, MRI
*)

(**
   This module parses the XML generated by running lib/sany.jar (which is
   generated by the toolbox
*)

open Commons
open Xmlm
open Sany_ds
open Xml_utils

let init_context_map ls = ContextMap.empty

let mkLevel i = match i with
  | 0 -> ConstantLevel
  | 1 -> StateLevel
  | 2 -> TransitionLevel
  | 3 -> TemporalLevel
  | _ -> failwith ("XML Parser error: unknown level " ^
                   (string_of_int i) ^ " (expected 0-3).")

let opdeclkind_from_int i = match i with
  | 2 -> ConstantDecl
  | 3 -> VariableDecl
  | 4 -> BoundSymbol
  | 24 -> NewConstant
  | 25 -> NewVariable
  | 26 -> NewState
  | 27 -> NewAction
  | 28 -> NewTemporal
  | n -> failwith ("Conversion from int to operator declaration type failed. " ^
                   "The number " ^ (string_of_int n) ^
                   " does not represent a proper declaration.")


(** Parses a location node, returning a record with line and column *)
let read_location i : location =
  open_tag i "location";
  open_tag i "column";
  let cb = get_data_in i "begin" read_int in
  let ce = get_data_in i "end" read_int in
  close_tag i "column";
  open_tag i "line";
  let lb = get_data_in i "begin" read_int in
  let le = get_data_in i "end" read_int in
  close_tag i "line";
  let fname = get_data_in i "filename" read_string in
  close_tag i "location";
  { column = {rbegin = cb; rend = ce};
    line = {rbegin = lb; rend = le};
    filename = fname
  }

(** Parses a location, if there is one *)
let read_optlocation i : location option =
  match get_optchild i "location" read_location with
  | [] -> None
  | [x] -> Some x
  | x -> failwith ("Implementation error in XML parsing: the reader for 0 or " ^
                   "1 elements returned multiple elements" )

(** Parses an optional level node *)
let get_optlevel i =
  match get_optchild i "level" (fun i -> get_data_in i "level" read_int) with
  | [] -> None
  | [x] -> Some (mkLevel x)
  | x -> failwith ("Implementation error in XML parsing: the reader for 0 or " ^
                   "1 elements returned multiple elements")

(** Parses the FormalParamNode within context/entry *)
let read_formal_param i : formal_param_ =
  open_tag i "FormalParamNode";
  let loc = read_optlocation i in
  let level = get_optlevel i in
  let un = get_data_in i "uniquename" read_string in
  let ar = get_data_in i "arity" read_int in
  close_tag i "FormalParamNode";
  {
    location = loc;
    level = level;
    arity = ar;
    name = un;
  }

(** gets the UID number of the reference node "name" *)
let read_ref i name f =
  open_tag i name;
  open_tag i "UID";
  let str = read_int i in
  close_tag i "UID";
  close_tag i name;
  f str

(** reads one of reference arguments *)
let read_opref i =
  let name = match (peek i) with
    | `El_start ((_, name),_ ) -> name
    | signal -> failwith ("We expect a symbol opening tag of an operator "^
                          "reference but got " ^ (formatSignal signal))
  in
  let rr = read_ref i name in
  let opref = match name with
    | "FormalParamNodeRef"    -> rr (fun x -> FMOTA_formal_param (FP_ref x) )
    | "ModuleNodeRef"         -> rr (fun x -> FMOTA_module (MOD_ref x) )
    | "OpDeclNodeRef"         -> rr (fun x -> FMOTA_op_decl (OPD_ref x) )
    | "ModuleInstanceKindRef" ->
      rr (fun x -> FMOTA_op_def (OPDef (O_module_instance (MI_ref x) )))
    | "UserDefinedOpKindRef"  ->
      rr (fun x -> FMOTA_op_def (OPDef (O_user_defined_op (UOP_ref x) )))
    | "BuiltInKindRef"        ->
      rr (fun x -> FMOTA_op_def (OPDef (O_builtin_op (BOP_ref x)) ))
    | "TheoremDefRef"        ->
      rr (fun x -> FMOTA_op_def (OPDef (O_thm_def (TDef_ref x) )))
    | "AssumeDefRef"         ->
      rr (fun x -> FMOTA_op_def (OPDef (O_assume_def (ADef_ref x) )))
    | _ -> failwith ("Found tag " ^ name ^
                     " but we need an operator reference ("^
                     "FormalParamNodeRef, ModuleNodeRef, OpDeclNodeRef, " ^
                     "ModuleInstanceKindRef, UserDefinedOpKindRef, " ^
                     "BuiltInKindRef, TheoremNodeRef, AssumeNodeRef)")
  in
  opref


(** handles the leibnizparam tag *)
let read_param i =
  open_tag i "leibnizparam";
  let wrap_fp x = FP_ref x in
  let fpref = read_ref i "FormalParamNodeRef" wrap_fp in
  let is_leibniz = read_flag i "leibniz"  in
  let ret = (fpref, is_leibniz) in
  close_tag i "leibnizparam";
  ret

let read_params i =
  get_children_in i "params" "leibnizparam" read_param

(** Parses the BuiltinKind within context/entry *)
let read_builtin_kind i =
  open_tag i "BuiltInKind";
  let loc = read_optlocation i in
  let level = get_optlevel i in
  let un = get_data_in i "uniquename" read_string in
  let ar = get_data_in i "arity" read_int in
  let params = get_children i "params" read_params in
  close_tag i "BuiltInKind";
  BOP {
    location = loc;
    arity = ar;
    name = un;
    params = List.flatten params;
    level = level;
  }

(* untested *)
let read_module_instance i : module_instance =
  open_tag i "ModuleInstanceKind";
  let loc = read_optlocation i in
  let level = get_optlevel i in
  let un = get_data_in i "uniquename" read_string in
  close_tag i "ModuleInstanceKind";
  MI {
    location = loc;
    level    = level;
    name     = un;
  }


(* --- expressions parsing is mutually recursive (e.g. OpApplNode Expr) ) --- *)
let rec read_expr i =
  let name = match (peek i) with
    | `El_start ((_, name),_ ) -> name
    | _ -> failwith "We expect symbol opening tag in an entry."
  in
  let expr = match name with
    | "AtNode"      -> E_at (read_at i)
    | "DecimalNode" -> E_decimal (read_decimal i)
    | "LabelNode"   -> E_label (read_label i)
    | "LetInNode"   -> E_let_in (read_let i)
    | "NumeralNode" -> E_numeral (read_numeral i)
    | "OpApplNode"  -> E_op_appl (read_opappl i)
    | "StringNode"  -> E_string (read_stringnode i)
    | "SubstInNode" -> E_subst_in (read_substinnode i)
    | _ -> failwith ("Unexpected node start tag for expression " ^ name ^
                     ", expected one of AtNode, DecimalNode, LabelNode, "^
                     " LetInNode, NumeralNode, OpApplNode, StringNode "^
                     " or SubstInNode." )
  in
  expr

(* This is different from the xsd file which allows expression and oparg nodes.
   The java at node code has only opapp (which are expressions) children though.
*)
and read_at i =
  open_tag i "AtNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let except = read_opappl i  in
  let except_component = read_opappl i in
  close_tag i "AtNode";
  {
    location          = location;
    level             = level;
    except            = except;
    except_component  = except_component;
  }

and read_decimal i =
  open_tag i "DecimalNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let mantissa = get_data_in i "mantissa" read_int in
  let exponent = get_data_in i "exponent" read_int in
  close_tag i "DecimalNode";
  {
    location  = location;
    level     = level;
    mantissa  = mantissa;
    exponent  = exponent;
  }
(* untested *)
and read_label i =
  open_tag i "LabelNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let name = get_data_in i "uniquename" read_string in
  let arity = get_data_in i "arity" read_int in
  open_tag i "body";
  let body = read_expr_or_assumeprove i in
  close_tag i "body";
  open_tag i "params";
  let params = get_children i "params"
      (fun i -> read_ref i "FormalParamNodeRef" (fun x -> FP_ref x)) in
  close_tag i "params";
  close_tag i "LabelNode";
  {
    location  = location;
    level     = level;
    name      = name;
    arity     = arity;
    body      = body;
    params    = params;
  }

(* there are no test cases for this yet *)
and read_let i :let_in	=
  open_tag i "LetInNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let body = get_data_in i "body" read_expr in
  let mkOPDrefM x = OTA_op_def (OPDef (O_module_instance (MI_ref x))) in
  let mkOPDrefU x = OTA_op_def (OPDef (O_user_defined_op (UOP_ref x))) in
  let mkOPDrefB x = OTA_op_def (OPDef (O_builtin_op (BOP_ref x))) in
  let mkAref x = OTA_assume (ASSUME_ref x) in
  let mkTref x = OTA_theorem (THM_ref x) in
  let mkRef name f inp = read_ref inp name f in
  let op_defs = get_children_choice_in i "opDefs" [
      ((=) "ModuleInstanceKindRef", mkRef "ModuleInstanceKindRef" mkOPDrefM);
      ((=) "UserDefinedOpKindRef",  mkRef "UserDefinedOpKindRef" mkOPDrefU);
      ((=) "BuiltInKindRef",        mkRef "BuiltInKindRef" mkOPDrefB);
      ((=) "AssumeNodeRef",         mkRef "AssumeNodeRef" mkAref);
      ((=) "TheoremNodeRef",        mkRef "TheoremNodeRef" mkTref);
    ] in
  close_tag i "LetInNode";
  {
    location = location;
    level    = level;
    body     = body;
    op_defs  = op_defs;
  }

and read_numeral i : numeral =
  open_tag i "NumeralNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let value = get_data_in i "IntValue" read_int in
  close_tag i "NumeralNode";
  {
    location = location;
    level = level;
    value = value;
  }

and read_opappl i =
  open_tag i "OpApplNode";
  let loc = read_optlocation i in
  let level = get_optlevel i in
  let opref = get_data_in i "operator" read_opref in
  let operands = get_data_in i "operands" (fun i ->
      get_children_choice i [
        ((=) "OpArgNode", (fun i -> EO_op_arg (read_oparg i)));
        ((fun x -> true), (fun i -> EO_expr (read_expr i)) )
      ])
  in
  let bound_symbols = match (peek i) with
    | `El_start ((_,name), _) ->
      open_tag i "boundSymbols";
      let handle_unbound i =
        B_unbounded_bound_symbol (read_unbounded_param i) in
      let handle_bound i =
        B_bounded_bound_symbol (read_bounded_param i) in
      let bs =
        get_children_choice i [
          ((=) "unbound", handle_unbound );
          ((=) "bound", handle_bound
          )  ]
      in
      close_tag i "boundSymbols";
      bs
    | _ -> []
  in
  let ret =  {
    location = loc;
    level = level;
    operator = opref;
    operands = operands;
    bound_symbols = bound_symbols;
  }
  in
  close_tag i "OpApplNode";
  ret

and read_stringnode i : strng =
  open_tag i "StringNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  open_tag i "StringValue";
  let value = match (peek i) with
    | `El_end -> ""  (* we accept empty strings as string values *)
    | _       -> read_string i in
  close_tag i "StringValue";
  close_tag i "StringNode";
  {
    location = location;
    level = level;
    value = value;
  }


and read_subst i =
  open_tag i "Subst";
  let op = read_ref i "OpDeclNodeRef" (fun x -> OPD_ref x) in
  let expr = get_child_choice i [
      (is_expr_node, (fun i -> EO_expr (read_expr i)));
      ((=)"OpArgNode", (fun i -> EO_op_arg (read_oparg i)));
    ] in
  close_tag i "Subst";
  {
    op = op;
    expr = expr;
  }

and read_substinnode i : subst_in =
  open_tag i "SubstInNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let substs = get_children_in i "substs" "Subst" read_subst in
  open_tag i "body";
  let body = read_expr i in
  close_tag i "body";
  close_tag i "SubstInNode";
  {
    location = location;
    level    = level;
    substs   = substs;
    body     = body;
  }

(* untested *)
and read_instance i  =
  open_tag i "InstanceNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let get_uname i = get_data_in i "uniquename" read_string in
  let name  =
    match get_optchild i "uniquename" get_uname with
    | [] -> None
    | [child] -> Some child
    | _ -> failwith "Implementation error in get_optchild!"
  in
  let module_name  = get_data_in i "module" read_string in
  let substs = get_children_in i "substs" "Subst" read_subst in
  let params = get_children_in i "params" "FormalParamNodeRef"
      (fun i-> read_ref i "FormalParamNodeRef" (fun x -> FP_ref x))
  in
  close_tag i "InstanceNode";
  {
    location;
    level;
    name;
    module_name;
    substs;
    params;
  }

and is_node name =
  is_expr_node name
  || is_proof_node name
  || (List.mem name
        ["APSubstInNode"; "AssumeProveNode"; "DefStepNode";
         "OpArgNode"; "InstanceNode"; "NewSymbNode";
         "FormalParamNodeRef"; "ModuleNodeRef"; "OpDeclNodeRef";
         "ModuleInstanceKindRef"; "UserDefinedOpKindRef"; "BuiltInKindRef";
         "AssumeNodeRef"; "TheoremNodeRef"; "UseOrHideNode"; ])

and read_node i = get_child_choice i [
    ((=) "APSubstInNode",   fun i -> N_ap_subst_in (read_apsubstinnode i));
    ((=) "AssumeProveNode", fun i -> N_assume_prove (read_assume_prove i));
    (is_expr_node,          fun i -> N_expr (read_expr i));
  ]

(* untested *)
and read_apsubstinnode i : ap_subst_in =
  open_tag i "APSubstInNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let substs = get_children_in i "substs" "Subst" read_subst in
  open_tag i "body";
  let body = get_child_choice i [(is_node, read_node)] in
  close_tag i "body";
  close_tag i "APSubstInNode";
  {
    location = location;
    level    = level;
    substs   = substs;
    body = body;
  }

and read_tuple i : bool = match (peek i) with
  | `El_start ((_,"tuple"), _) ->
    (* if tag is present, consume tag and return true*)
    open_tag i "tuple";
    close_tag i "tuple";
    true
  | _ ->  (* otherwise return false *)
    false

and read_bounded_param i : bounded_bound_symbol =
  open_tag i "bound";
  let params = get_children i "FormalParamNodeRef"
      (fun i -> read_ref i "FormalParamNodeRef" (fun x -> FP_ref x)) in
  let tuple = read_tuple i in
  let domain = read_expr i in
  let ret =  {
    params = params;
    tuple = tuple;
    domain = domain;
  } in
  close_tag i "bound";
  ret

and read_unbounded_param i : unbounded_bound_symbol =
  open_tag i "unbound";
  let params = read_ref i "FormalParamNodeRef" (fun x -> FP_ref x) in
  let tuple = read_tuple i in
  let ret =  {
    param = params;
    tuple = tuple;
  } in
  close_tag i "unbound";
  ret

and read_assume_def i =
  open_tag i "AssumeDef";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let name = get_data_in i "uniquename" read_string in
  let body = read_expr i in
  close_tag i "AssumeDef";
  let r : assume_def_ = {
    location;
    level;
    name;
    body;
  }
  in ADef r

and read_assume i : assume_ =
  open_tag i "AssumeNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let opt_def =  get_optchild i "definition"
      (fun i ->
         open_tag i "definition";
         let r = read_opref i in
         close_tag i "definition";
         r
      )
  in
  open_tag i "body";
  let expr = read_expr i in
  close_tag i "body";
  close_tag i "AssumeNode";
  let definition = match opt_def with
    | [ FMOTA_op_def (OPDef (O_assume_def t)) ] ->
      Some t
    | [] ->
      None
    | _ -> failwith "Implementation error reading assume node!"
  in
  let asm = { location; level; definition; expr; }
  in asm


and expr_nodes =
  ["AtNode"      ;   "DecimalNode" ;   "LabelNode"   ;
   "LetInNode"   ;   "NumeralNode" ;   "OpApplNode"  ;
   "StringNode"  ;   "SubstInNode" ;   "TheoremDefNode";
   "AssumeDef"; ]

and is_expr_node name = List.mem name expr_nodes

(* --- end of mutual recursive expression parsing --- *)


(** reads the definition of a user defined operator within context/entry *)
and read_userdefinedop_kind i  =
  open_tag i "UserDefinedOpKind";
  let loc = read_optlocation i in
  let level = get_optlevel i in
  let un = get_data_in i "uniquename" read_string in
  let ar = get_data_in i "arity" read_int in
  let body = get_data_in i "body" read_expr in
  let params = List.flatten
      (get_optchild i "params" read_params) in
  let recursive = read_flag i "recursive" in
  let ret = UOP {
      location = loc;
      arity = ar;
      name = un;
      level = level;
      body = body;
      params = params;
      recursive = recursive;
    } in
  close_tag i "UserDefinedOpKind";
  ret

and read_op_decl i =
  open_tag i "OpDeclNode";
  let loc = read_optlocation i in
  let level = get_optlevel i in
  let un = get_data_in i "uniquename" read_string in
  let ar = get_data_in i "arity" read_int in
  let kind = opdeclkind_from_int (get_data_in i "kind" read_int) in
  close_tag i "OpDeclNode";
  {
    location = loc;
    level = level;
    name = un;
    arity = ar;
    kind = kind;
  }

and read_newsymb i =
  open_tag i "NewSymbNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let op_decl = OPD_ref (read_ref i "OpDeclNodeRef" (fun x->x)) in
  let exprl = get_optchild_choice i [
      (is_expr_node, read_expr);
    ] in
  let set = match exprl with
    | [e] -> Some e
    | [] -> None
    | _ -> failwith "An option expression returned more than 1 result."
  in
  close_tag i "NewSymbNode";
  {
    location = location;
    level    = level;
    op_decl  = op_decl;
    set      = set;
  }

and read_assume_prove i =
  open_tag i "AssumeProveNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let assumes = get_children_choice_in i "assumes"  [
      ((=) "AssumeProveNode", (fun i -> NEA_assume_prove (read_assume_prove i)));
      ((=) "NewSymbNode", (fun i -> NEA_new_symb (read_newsymb i)));
      (is_expr_node , (fun i -> NEA_expr (read_expr i)));
    ] in
  open_tag i "prove";
  let prove = get_child_choice i [(is_expr_node, read_expr)] in
  close_tag i "prove";
  let suffices = read_flag i "suffices" in
  let boxed = read_flag i "boxed" in
  close_tag i "AssumeProveNode";
  {
    location = location;
    level    = level;
    assumes  = assumes;
    prove    = prove;
    suffices = suffices;
    boxed    = boxed;
  }

and read_omitted i : omitted =
  open_tag i "omitted";
  let location = read_optlocation i in
  let level = get_optlevel i in
  close_tag i "omitted";
  {
    location = location;
    level = level;
  }

and read_obvious i : obvious =
  open_tag i "obvious";
  let location = read_optlocation i in
  let level = get_optlevel i in
  close_tag i "obvious";
  {
    location = location;
    level = level;
  }

and read_facts i =
  let id = (fun x -> x) in
  get_children_choice_in i "facts" [
    ((=) "ModuleNodeRef", (fun i -> EMM_module
                              (MOD_ref (read_ref i "ModuleNodeRef" id))));
    ((=) "ModuleInstanceKind", (fun i -> EMM_module_instance
                                   (read_module_instance i)));
    (is_expr_node, (fun i -> EMM_expr (read_expr i)));
  ]

and read_defs i =
  let id = (fun x -> x) in
  get_children_choice_in i "defs" [
    ((=) "UserDefinedOpKindRef", (fun i -> UMTA_user_defined_op
                                     (UOP_ref (read_ref i "UserDefinedOpKindRef" id) )));
    ((=) "ModuleInstanceKindRef", (fun i -> UMTA_module_instance
                                      (MI_ref (read_ref i "ModuleInstanceKindRef" id) ) ));
    ((=) "TheoremDefRef", (fun i -> UMTA_theorem_def
                               (TDef_ref (read_ref i "TheoremDefRef" id) )));
    ((=) "AssumeDefRef", (fun i -> UMTA_assume_def
                              (ADef_ref (read_ref i "AssumeDefRef" id) )));
  ]

and read_by i =
  open_tag i "by";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let facts = read_facts i in
  let defs = read_defs i in
  let only = read_flag i "only"  in
  close_tag i "by";
  {
    location = location;
    level = level;
    facts = facts;
    defs = defs;
    only = only;
  }


and read_useorhide i : use_or_hide =
  open_tag i "UseOrHideNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let facts = read_facts i in
  let defs = read_defs i in
  let only = read_flag i "only" in
  let hide = read_flag i "hide" in
  close_tag i "UseOrHideNode";
  {
    location = location;
    level    = level;
    facts    = facts;
    defs     = defs;
    only     = only;
    hide     = hide;
  }

and read_steps i =
  open_tag i "steps";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let id = fun x -> x in
  let steps = get_children_choice i [
      ((=) "DefStepNode",    (fun i -> S_def_step (read_defstep i)));
      ((=) "UseOrHideNode",  (fun i -> S_use_or_hide (read_useorhide i)));
      ((=) "InstanceNode",   (fun i -> S_instance (read_instance i)));
      ((=) "TheoremNodeRef", (fun i -> S_theorem
                                 (THM_ref (read_ref i "TheoremNodeRef" id))));
      (*      ((=) "TheoremNode",    (fun i -> S_theorem (read_theorem i))); no thms as steps anymore *)
    ] in
  close_tag i "steps";
  {
    location = location;
    level = level;
    steps = steps;
  }

and read_defstep i   =
  open_tag i "DefStepNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let mkRefM name inp =
    read_ref inp name (fun x -> OPDef (O_module_instance (MI_ref x))) in
  let mkRefU name inp =
    read_ref inp name (fun x -> OPDef (O_user_defined_op (UOP_ref  x))) in
  let mkRefB name inp =
    read_ref inp name (fun x -> OPDef (O_builtin_op (BOP_ref x))) in
  let defs = get_children_choice i [
      ((=) "ModuleInstanceKindRef", mkRefM "ModuleInstanceKindRef");
      ((=) "UserDefinedOpKindRef", mkRefU "UserDefinedOpKindRef");
      ((=) "BuiltInKindRef", mkRefB "BuiltInKindRef");
    ] in
  close_tag i "DefStepNode";
  {
    location = location;
    level    = level;
    defs     = defs;
  }

and read_proof i =
  let ret = get_child_choice i [
      ((=) "omitted", (fun i -> P_omitted (read_omitted i)));
      ((=) "obvious", (fun i -> P_obvious (read_obvious i)));
      ((=) "by",      (fun i -> P_by (read_by i)));
      ((=) "steps",   (fun i -> P_steps (read_steps i)));
    ] in
  ret

and is_proof_node name = List.mem name ["omitted"; "obvious"; "by"; "steps"]

and read_expr_or_assumeprove i =
  get_child_choice i [
    ((=) "AssumeProveNode", (fun i -> EA_assume_prove (read_assume_prove i)));
    ((=) "APSubstInNode", (fun i -> EA_ap_subst_in (read_apsubstinnode i)));
    (is_expr_node , (fun i -> EA_expr (read_expr i)));
  ]

and read_theorem_def i =
  open_tag i "TheoremDefNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let name = get_data_in i "uniquename" read_string in
  let body = read_expr_or_assumeprove i in
  close_tag i "TheoremDefNode";
  let r : theorem_def_ = {
    location;
    level;
    name;
    body;
  }
  in TDef r

and read_theorem i : theorem_ =
  open_tag i "TheoremNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  let opt_def =  get_optchild i "definition"
      (fun i ->
         open_tag i "definition";
         let r = read_opref i in
         close_tag i "definition";
         r
      )
  in
  open_tag i "body";
  let expr = read_expr_or_assumeprove i in
  close_tag i "body";
  let proofl = get_optchild_choice i [(is_proof_node, read_proof)]  in
  let proof = match proofl with
    | [p] -> p
    | _   -> P_noproof
  in
  let suffices = read_flag i "suffices" in
  close_tag i "TheoremNode";
  let definition = match opt_def with
    | [ FMOTA_op_def (OPDef (O_thm_def t)) ] ->
      Some t
    | [] ->
      None
    | _ -> failwith "Implementation error reading assume node!"
  in
  let thm = {
    location;
    level;
    definition;
    expr;
    proof;
    suffices;
  } in thm

and read_module_entries i =
  let read_varconst_ref i = read_ref i "OpDeclNodeRef"
      (fun x -> MODe_op_decl (OPD_ref x) ) in
  let mkOpdefrefHandlerM name i =
    read_ref i name (fun x -> MODe_op_def
                        (OPDef (O_module_instance (MI_ref x)))) in
  let mkOpdefrefHandlerU name i =
    read_ref i name (fun x -> MODe_op_def
                        (OPDef (O_user_defined_op (UOP_ref x)))) in
  let mkOpdefrefHandlerB name i =
    read_ref i name (fun x -> MODe_op_def (OPDef (O_builtin_op (BOP_ref x)))) in
  let mkAssumerefHandler name i =
    read_ref i name (fun x -> MODe_assume (ASSUME_ref x)) in
  let handle_table =
    [
      (* declarations *)
      ((=) "OpDeclNodeRef", read_varconst_ref);
      (* definitions *)
      ((=) "ModuleNodeRef", mkOpdefrefHandlerM "ModuleNodeRef") ;
      ((=) "UserDefinedOpKindRef", mkOpdefrefHandlerU "UserDefinedOpKindRef")  ;
      ((=) "BuiltInKindRef",       mkOpdefrefHandlerB "BuiltInKindRef")  ;
      (* assumptions *)
      ((=) "AssumeNodeRef", mkAssumerefHandler "AssumeNodeRef");
      (* instances *)
      ((=) "InstanceNode", fun i -> MODe_instance (read_instance i));
      (* use_or_hides *)
      ((=) "UseOrHideNode", fun i -> MODe_use_or_hide (read_useorhide i));
      (* theorems *)
      ((=) "TheoremNodeRef",
       fun i -> read_ref i "TheoremNodeRef"
           (fun x -> MODe_theorem (THM_ref x)) );
      ((=) "TheoremNode", fun i -> failwith "only thm refs in modules!");
      ((=) "AssumeNode", fun i -> failwith "only assume refs in modules!");
    ] in
  get_children_choice i handle_table

and read_module_ i =
  open_tag i "ModuleNode";
  let location = get_child i "location" read_optlocation in
  let name = get_data_in i "uniquename" read_string in
  let module_entries = read_module_entries i in
  let ret = {
      location;
      name;
      module_entries;
    } in
  close_tag i "ModuleNode";
  ret

and read_module_ref i =
  read_ref i "ModuleNodeRef" (fun x -> MOD_ref x)

(*
and read_module i =
  get_child_choice i [
    ((=) "ModuleNode", read_module_);
    ((=) "ModuleNodeRef", read_module_ref)
  ]
*)

(* User defined operator definition nodes:
   ModuleInstanceKind, UserDefinedOpKind, BuiltinKind
*)
and read_op_def i =
  get_child_choice i [
    ((=) "UserDefinedOpKind" , (fun i -> OPDef
                                   (O_user_defined_op (read_userdefinedop_kind i))));
    ((=) "ModuleInstanceKind", (fun i -> OPDef
                                   (O_module_instance (read_module_instance i))));
    ((=) "BuiltInKind"       , (fun i -> OPDef
                                   (O_builtin_op (read_builtin_kind i))));
    ((=) "AssumeDef"         , (fun i -> OPDef
                                   (O_assume_def (read_assume_def i))));
    ((=) "TheoremDefNode"    , (fun i -> OPDef
                                   (O_thm_def (read_theorem_def i))));
  ]


and read_op_def_ref i =
  get_child_choice i [
    ((=) "UserDefinedOpKindRef" , (fun i -> OPDef
                                      (O_user_defined_op
                                         (read_ref i "UserDefinedOpKindRef"
                                         (fun x -> UOP_ref x)))));
    ((=) "ModuleInstanceKindRef", (fun i -> OPDef
                                      (O_module_instance
                                         (read_ref i "ModuleInstanceKindRef"
                                            (fun x -> MI_ref x)))));
    ((=) "BuiltInKindRef"       , (fun i -> OPDef
                                      (O_builtin_op
                                         (read_ref i "BuiltInKindRef"
                                            (fun x -> BOP_ref x)))));
    ((=) "TheoremDefRef"       , (fun i -> OPDef
                                      (O_thm_def
                                         (read_ref i "TheoremDefRef"
                                            (fun x -> TDef_ref x)))));
    ((=) "AssumeDefRef"       , (fun i -> OPDef
                                      (O_assume_def
                                         (read_ref i "AssumeDefRef"
                                            (fun x -> ADef_ref x)))));
  ]

and is_op_def name = List.mem name
    ["UserDefinedOpKind"; "ModuleInstanceKind"; "BuiltInKind"; "AssumeDef";
     "TheoremDefNode"]

and is_op_def_ref name = List.mem name
    ["UserDefinedOpKindRef"; "ModuleInstanceKindRef"; "BuiltInKindRef";
     "AssumeDefRef"; "TheoremDefRef"]

(** Parses the OpArgNode *)
and read_oparg i : op_arg =
  open_tag i "OpArgNode";
  let location = read_optlocation i in
  let level = get_optlevel i in
  (*  let un = get_data_in i "uniquename" read_string in *)
  (* let arity = get_data_in i "arity" read_int in *)
  open_tag i "argument";
  let argument = get_child_choice i [
      ((=)  "APSubstInNode"  , (fun i ->  FMOTA_ap_subst_in
                                   (read_apsubstinnode i)));
      ((=)  "FormalParamNodeRef", (fun i ->  FMOTA_formal_param
                                      (read_ref i "FormalParamNodeRef"
                                         (fun x -> FP_ref x))));
      (is_op_def_ref         , (fun i ->  FMOTA_op_def (read_op_def_ref i)));
      ((=)  "ModuleNodeRef"  , (fun i ->  FMOTA_module
                                   (read_ref i "ModuleNodeRef"
                                      (fun x -> MOD_ref x))));
      ((=)  "OpDeclNodeRef"  , (fun i ->  FMOTA_op_decl
                                   (read_ref i "OpDeclNodeRef"
                                      (fun x -> OPD_ref x))));
    ] in
  close_tag i "argument";
  close_tag i "OpArgNode";
  { location; level; argument;  }


and read_entry i =
  open_tag i "entry";
  let uid = get_data_in i "UID" read_int in
  let symbol = get_child_choice i [
      ((=)  "FormalParamNode", (fun i ->  E_formal_param
                                   (read_formal_param i)));
      (is_op_def             , (fun i ->
           match read_op_def i with
           | OPDef (O_user_defined_op (UOP op)) -> E_user_defined_op op
           | OPDef (O_builtin_op (BOP op)) -> E_builtin_op op
           | OPDef (O_module_instance (MI op)) -> E_module_instance op
           | OPDef (O_assume_def (ADef op)) -> E_assume_def op
           | OPDef (O_thm_def (TDef op)) -> E_thm_def op
           | _ ->
             failwith "Cannot have references as entry in the has table"
         ));
      ((=)  "ModuleNode"     , (fun i ->  E_module  (read_module_ i)));
      ((=)  "OpDeclNode"     , (fun i ->  E_op_decl (read_op_decl i)  ));
      ((=)  "TheoremNode"    , (fun i ->  E_theorem (read_theorem i)));
      ((=)  "AssumeNode"     , (fun i ->  E_assume  (read_assume i)));
    ] in
  close_tag i "entry";
  {
    uid = uid;
    reference = symbol;
  }

let read_modules i =
  open_tag i "modules";
  let root_module = get_data_in i "RootModule" read_string in
  let entries = get_children_in i "context" "entry" read_entry in
  let modules = get_children_choice i
      [((=) "ModuleNodeRef", read_module_ref)]
  in
  close_tag i "modules";
  { root_module; entries; modules; }

let read_header i =
  input i (* first symbol is dtd *)

(*while true do match (input i) with
  | `Data d -> print_string ("data: " ^ d ^ "\n")
  | `Dtd d -> print_string "dtd\n"
  | `El_start d -> print_string ("start: " ^ (snd(fst d)) ^ "\n")
  | `El_end -> print_string "end\n"
  done*)

let import_xml ic =
  let i = Xmlm.make_input (`Channel ic) in
  let _ = read_header i in
  read_modules i
(*while not (Xmlm.eoi i) do match (Xmlm.input i) with
  done;
  assert false*)
