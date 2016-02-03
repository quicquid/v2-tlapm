open Kaputt.Abbreviations
open Commons
open Expr_ds
open Extract_obligations
open Util
open Test_common
open Format
open Obligation
open Obligation_formatter


let fmt_prover = function
  | Isabelle -> "Isabelle"
  | Zenon -> "Zenon"
  | SMT -> "SMT"
  | LS4 -> "LS4"
  | Default -> "Default provers"

let test_extract_obligations record () =
  ignore (
      let context = match record.explicit_steps_context with
        | Some c -> c
        | None ->
           failwith ("Test implementation error! No expression context "^
                     "with corrected proof steps " ^
                     "available in record for file " ^ record.filename )
      in
      let cc = emptyCurrentContext context.entries in
      let eo = new extract_obligations in
      let (_,obs,_,_) = eo#context ([cc], [], Module, None) context in
      match obs with
      | [] -> Printf.printf "%s no obligations extracted!\n" record.filename;
      | _  ->
         (
         let total = List.length obs in
         let print_obl i o =
           let pstr = mkString fmt_prover (o.provers) in
           Printf.printf "Obligation #%d of %d\n" i total;
           Printf.printf "%s obligation provers : %s\n" record.filename pstr;
           (* Printf.printf "%d assumptions\n" (List.length o.goal.assumes); *)
           fmt_obligation std_formatter o;
           
           Printf.printf "\n(end of obligation)\n";
           i+1
         in
         ignore (
         Printf.printf "%s : no of obligations: %d\n" record.filename total;
         List.fold_left print_obl 1 obs
         )
         )
    )

let create_test record =
  Test.make_assert_test
    ~title: ("extracting obligations " ^ record.filename)
    (fun () -> ())
    (fun () ->
     Assert.no_raise ~msg:"Unexpected exception raised."
                     (fun () -> exhandler ( test_extract_obligations record )  )
    )
    (fun () -> ()  )


let get_tests records = List.map create_test records
