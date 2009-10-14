
(** Internal configure and install scheme for AutoBuild
    @author Sylvain Le Gall
  *)

open OASISTypes;;
open BasePlugin;;
open BaseUtils;;
open BaseGenCode;;

let plugin_id = "internal";;

(* Configuration *)
let configure pkg standard_vars =

  let build_depends_check acc = 
    function
      | FindlibPackage (findlib_pkg, ver_opt) ->
          (
            let version_arg = 
              match ver_opt with
                | Some ver ->
                    let cmp = 
                      BaseVersion.comparator_of_string ver
                    in
                      [
                        "version_comparator",
                        TPL [STR ver; 
                             BaseVersion.code_of_comparator cmp;
                             STR (BaseVersion.varname_of_comparator cmp)];
                      ]
                | None ->
                    []
            in
              APP ("BaseCheck.package", version_arg, [STR findlib_pkg]) :: acc
          )
      | InternalLibrary _ ->
          acc
  in

  let build_tools_check acc prog =
    APP ("BaseCheck.prog", [], [STR prog]) :: acc
  in

  let build_checks cond tools depends =
    TPL
      [
        (BaseExpr.code_of_bool_choices cond);
        LST
          (List.rev
             (List.fold_left 
                build_depends_check
                (List.fold_left
                   build_tools_check
                   []
                   tools)
                depends))
      ]
  in

  let build_depends_collect pkg =
   (build_checks 
      BaseExpr.condition_true
      pkg.build_tools 
      pkg.build_depends)
   ::
   (List.map 
     (fun (_, lib) -> 
        build_checks
          (BaseExpr.choices_of_oasis lib.lib_build)
          lib.lib_build_tools
          lib.lib_build_depends)
     pkg.libraries)
   @
   (List.map 
      (fun (_, exec) -> 
         build_checks 
           (BaseExpr.choices_of_oasis exec.exec_build)
           exec.exec_build_tools
           exec.exec_build_depends)
      pkg.executables)
  in

  let standard_vars_collect pkg = 
    TPL
      [BaseExpr.code_condition_true;
       LST
         (List.map
            (fun e ->
               let var = 
                 match e with 
                   | SVocamlc -> "ocamlc"
                   | SVocamlopt -> "ocamlopt"
                   | SVocamlbest -> "ocamlbest"
                   | SVsuffix_program -> "suffix_program"
                   | SVocaml_version -> "ocaml_version"
                   | SVstandard_library_default -> "standard_library_default"
                   | SVstandard_library -> "standard_library"
                   | SVstandard_runtime -> "standard_runtime"
                   | SVccomp_type -> "ccomp_type"
                   | SVbytecomp_ccompiler -> "bytecomp_ccompiler"
                   | SVbytecomp_c_linker -> "bytecomp_c_linker"
                   | SVbytecomp_c_libraries -> "bytecomp_c_libraries"
                   | SVnative_c_compiler -> "native_c_compiler"
                   | SVnative_c_linker -> "native_c_linker"
                   | SVnative_c_libraries -> "native_c_libraries"
                   | SVnative_partial_linker -> "native_partial_linker"
                   | SVranlib -> "ranlib"
                   | SVcc_profile -> "cc_profile"
                   | SVarchitecture -> "architecture"
                   | SVmodel -> "model"
                   | SVsystem -> "system"
                   | SVext_obj -> "ext_obj"
                   | SVext_asm -> "ext_asm"
                   | SVext_lib -> "ext_lib"
                   | SVext_dll -> "ext_dll"
                   | SVos_type -> "os_type"
                   | SVdefault_executable_name -> "default_executable_name"
                   | SVsysthread_supported -> "systhread_supported"
               in
                 VAR ("BaseStandardVar."^var))
            standard_vars)]
  in

  let ocaml_version_check pkg = 
    match pkg.ocaml_version with 
      | Some ver -> 
          (
            let cmp = 
              BaseVersion.comparator_of_string ver
            in
              [TPL
                 [BaseExpr.code_condition_true;
                  LST
                    [
                      APP ("BaseCheck.version",
                           [],
                           [
                             STR "ocaml";
                             TPL [STR ver; 
                                  BaseVersion.code_of_comparator cmp;
                                  STR (BaseVersion.varname_of_comparator cmp)];
                             VAR "BaseStandardVar.ocaml_version";
                           ])]]]
          )
      | None ->
          []
  in

  let code_checks = 
    LST (standard_vars_collect pkg :: build_depends_collect pkg @ ocaml_version_check pkg)
  in

  let code_flags =
    LST
      (List.map 
         (fun (nm, flg) ->
            TPL
              [STR nm; 
               (match flg.flag_description with
                  | Some hlp -> VRT("Some", [STR hlp])
                  | None     -> VRT("None", []));
               BaseExpr.code_of_choices
                 (function 
                    | true  -> STR "true"
                    | false -> STR "false")
                 (BaseExpr.choices_of_oasis flg.flag_default)])
         pkg.flags)
  in

  let code_files_ab =
    LST (List.map (fun f -> STR f) pkg.files_ab)
  in     

  let code = 
    APP
      ("InternalConfigure.configure",
       [],
       [
         STR pkg.name;
         STR pkg.version;
         code_flags;
         code_checks;
         code_files_ab
       ])
  in

    {
      moduls = 
        [
          BaseData.basesys_ml; 
          InternalData.internalsys_ml
        ];
      setup_code       = code;
      clean_code       = [];
      distclean_code   = [];
      other_action     = (fun _ -> ());
      files_generated  = (List.map BaseFileAB.to_filename pkg.files_ab);
      standard_vars    = [];
    }
;;

plugin_register plugin_id (Configure configure);;

(* Installation *)
let install pkg =

  let code =
    APP 
      ("InternalInstall.install",
       [],
       [
         LST 
           (List.map 
              InternalInstall.library_code_of_oasis 
              pkg.libraries);
         LST 
           (List.map 
              InternalInstall.executable_code_of_oasis 
              pkg.executables);
       ]
      )
  in

    {
      moduls = 
        [
          BaseData.basesys_ml; 
          InternalData.internalsys_ml
        ];
      setup_code       = code;
      clean_code       = [];
      distclean_code   = [];
      other_action     = (fun _ -> ());
      files_generated  = [];
      standard_vars    = [];
    },
    pkg
;;

plugin_register plugin_id (Install install);;
