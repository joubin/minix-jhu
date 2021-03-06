(* RUN: rm -rf %t.builddir
 * RUN: mkdir -p %t.builddir
 * RUN: cp %s %t.builddir
 * RUN: %ocamlopt -g -warn-error A llvm.cmxa llvm_target.cmxa llvm_executionengine.cmxa %t.builddir/target.ml -o %t
 * RUN: %t %t.bc
 * REQUIRES: native, object-emission
 * XFAIL: vg_leak
 *)

(* Note: It takes several seconds for ocamlopt to link an executable with
         libLLVMCore.a, so it's better to write a big test than a bunch of
         little ones. *)

open Llvm
open Llvm_target

let _ = Llvm_executionengine.initialize_native_target ()

let context = global_context ()
let i32_type = Llvm.i32_type context
let i64_type = Llvm.i64_type context

(* Tiny unit test framework - really just to help find which line is busted *)
let print_checkpoints = false

let _ =
  Printexc.record_backtrace true

let assert_equal a b =
  if a <> b then failwith "assert_equal"


(*===-- Fixture -----------------------------------------------------------===*)

let filename = Sys.argv.(1)
let m = create_module context filename

let target = Target.by_triple (Target.default_triple ())

let machine = TargetMachine.create (Target.default_triple ()) target

(*===-- Data Layout -------------------------------------------------------===*)

let test_target_data () =
  let module DL = DataLayout in
  let layout = "e-p:32:32:32-S32-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:32:64-" ^
               "f16:16:16-f32:32:32-f64:32:64-f128:128:128-v64:32:64-v128:32:128-" ^
               "a0:0:64-n32" in
  let dl     = DL.of_string layout in
  let sty    = struct_type context [| i32_type; i64_type |] in
  
  assert_equal (DL.as_string dl) layout;
  assert_equal (DL.byte_order dl) Endian.Little;
  assert_equal (DL.pointer_size dl) 4;
  assert_equal (DL.intptr_type context dl) i32_type;
  assert_equal (DL.qualified_pointer_size 0 dl) 4;
  assert_equal (DL.qualified_intptr_type context 0 dl) i32_type;
  assert_equal (DL.size_in_bits sty dl) (Int64.of_int 96);
  assert_equal (DL.store_size sty dl) (Int64.of_int 12);
  assert_equal (DL.abi_size sty dl) (Int64.of_int 12);
  assert_equal (DL.stack_align sty dl) 4;
  assert_equal (DL.preferred_align sty dl) 8;
  assert_equal (DL.preferred_align_of_global (declare_global sty "g" m) dl) 8;
  assert_equal (DL.element_at_offset sty (Int64.of_int 1) dl) 0;
  assert_equal (DL.offset_of_element sty 1 dl) (Int64.of_int 4);

  let pm = PassManager.create () in
  ignore (DL.add_to_pass_manager pm dl)


(*===-- Target ------------------------------------------------------------===*)

let test_target () =
  let module T = Target in
  ignore (T.succ target);
  ignore (T.name target);
  ignore (T.description target);
  ignore (T.has_jit target);
  ignore (T.has_target_machine target);
  ignore (T.has_asm_backend target)


(*===-- Target Machine ----------------------------------------------------===*)

let test_target_machine () =
  let module TM = TargetMachine in
  assert_equal (TM.target machine) target;
  assert_equal (TM.triple machine) (Target.default_triple ());
  assert_equal (TM.cpu machine) "";
  assert_equal (TM.features machine) "";
  ignore (TM.data_layout machine)


(*===-- Code Emission -----------------------------------------------------===*)

let test_code_emission () =
  TargetMachine.emit_to_file m CodeGenFileType.ObjectFile filename machine;
  try
    TargetMachine.emit_to_file m CodeGenFileType.ObjectFile
                               "/nonexistent/file" machine;
    failwith "must raise"
  with Llvm_target.Error _ ->
    ();

  let buf = TargetMachine.emit_to_memory_buffer m CodeGenFileType.ObjectFile
                                                machine in
  Llvm.MemoryBuffer.dispose buf


(*===-- Driver ------------------------------------------------------------===*)

let _ =
  test_target_data ();
  test_target ();
  test_target_machine ();
  (* test_code_emission (); *) (* broken without AsmParser support *)
  dispose_module m
