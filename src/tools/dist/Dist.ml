(******************************************************************************)
(* OASIS: architecture for building OCaml libraries and applications          *)
(*                                                                            *)
(* Copyright (C) 2011-2013, Sylvain Le Gall                                   *)
(* Copyright (C) 2008-2011, OCamlCore SARL                                    *)
(*                                                                            *)
(* This library is free software; you can redistribute it and/or modify it    *)
(* under the terms of the GNU Lesser General Public License as published by   *)
(* the Free Software Foundation; either version 2.1 of the License, or (at    *)
(* your option) any later version, with the OCaml static compilation          *)
(* exception.                                                                 *)
(*                                                                            *)
(* This library is distributed in the hope that it will be useful, but        *)
(* WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY *)
(* or FITNESS FOR A PARTICULAR PURPOSE. See the file COPYING for more         *)
(* details.                                                                   *)
(*                                                                            *)
(* You should have received a copy of the GNU Lesser General Public License   *)
(* along with this library; if not, write to the Free Software Foundation,    *)
(* Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA              *)
(******************************************************************************)

open OASISUtils
open OASISTypes

let () =
  let () = OASISBuiltinPlugins.init () in
  let debug_self = true in
  let exec nm =
    try
      FileUtil.which nm
    with Not_found ->
      failwithf "Executable '%s' not found." nm
  in
  let distdir = Filename.concat (Sys.getcwd ()) "dist" in
  let oasis_exec =
    let fn = FilePath.make_filename [(Sys.getcwd ()); "_build"; "src"; "cli"] in
    let native = Filename.concat fn "Main.native" in
    let byte = Filename.concat fn "Main.byte" in
    if Sys.file_exists native then
      native
    else
      byte
  in
  let git_exec = exec "git" in
  let tar_exec = exec "tar" in
  let dev = ref false in
  let () =
    (* Argument parsing. *)
    Arg.parse
      [
        "-dev",
        Arg.Set dev,
        " Generate a dev tarball.";
      ]
      (failwithf "Don't know what to do with %S")
      "dist.ml: build tarball for oasis."
  in
  let ctxt = {!OASISContext.default with OASISContext.ignore_plugins = true} in
  let run = OASISExec.run ~ctxt in
  let with_tmpdir f =
    let res = Filename.temp_file "oasis-dist-" ".dir" in
    let pwd = Sys.getcwd () in
    let clean () =
      Sys.chdir pwd;
      FileUtil.rm ~recurse:true [res]
    in
    Sys.remove res;
    OASISFileUtil.mkdir ~ctxt res;
    try
      f res;
      clean ()
    with e ->
      clean ();
      raise e
  in
  let pkg = OASISParse.from_file ~ctxt OASISParse.default_oasis_fn in
  let uncommited_changes =
    match OASISExec.run_read_output ~ctxt
            git_exec ["status"; "--porcelain"] with
    | [] -> false
    | _ -> true
  in
  let () =
    if not debug_self && uncommited_changes then
      failwith "Uncommited changes."
  in
  let ver_str = OASISVersion.string_of_version pkg.version in
  let () =
    (* Verify that the built oasis match the version in _oasis. *)
    let exec_ver_str =
      OASISExec.run_read_one_line ~ctxt oasis_exec ["version"]
    in
    if exec_ver_str <> ver_str then
      failwithf
        "Version reported by %s (%S) is different from version in _oasis (%S)"
        oasis_exec exec_ver_str ver_str
  in
  let tag = if !dev then "dev" else ver_str in
  let topdir = pkg.name^"-"^tag in
  let tarball = Filename.concat distdir (topdir^".tar.gz") in
    if not !dev then begin
      let existing_tags = OASISExec.run_read_output ~ctxt git_exec ["tag"] in
      let most_recent_tag =
        List.fold_left
          (fun r e ->
             if OASISVersion.StringVersion.compare r e < 0 then
               e
             else
               r)
          tag existing_tags
      in
      print_endline ("Most recent tag: "^most_recent_tag);
      if List.mem tag existing_tags then
        failwithf "Tag %s already exists." tag;
      if most_recent_tag <> tag then
        failwithf
        "Tag %S is more recent than the tag %S to apply."
        most_recent_tag tag
    end;

    (* Create the tarball. *)
    run git_exec
      ["archive"; "--prefix";  (Filename.concat topdir "");
       "--format"; "tar.gz"; "HEAD"; "-o"; tarball];
    with_tmpdir
      (fun dn ->
         (* Uncompress tarball in tmpdir *)
         run tar_exec ["xz"; "-C"; dn; "-f"; tarball];

         (* Run OASIS setup inside the tarball and rebuild it. *)
         run oasis_exec ["-C"; Filename.concat dn topdir; "setup"];
         run tar_exec ["-C"; dn; "-czf"; tarball; topdir];

         Sys.chdir (Filename.concat dn topdir);
         if Sys.file_exists "setup.data" then
           failwith "Remaining 'setup.data' file.";
         if Sys.file_exists "configure" &&
            not (FileUtil.test FileUtil.Is_exec "configure") then
           failwith "'configure' is not executable.";
         if not !dev then
           (* Check that build, test, doc run smoothly *)
           run "ocaml" ["setup.ml"; "-all"];
         let bak_files =
           (* Check for remaining .bak files *)
           FileUtil.find (FileUtil.Has_extension "bak")
             Filename.current_dir_name
             (fun acc fn -> fn :: acc)
             []
         in
           if bak_files <> [] then
             failwithf
               "Remaining .bak files: %s."
               (String.concat ", " bak_files));
    if not !dev then begin
      run git_exec ["tag"; tag];
      run
        ~f_exit_code:
        (fun i ->
           if i <> 0 then
             OASISMessage.warning ~ctxt "Cannot sign '%s' with gpg" tarball)
        "gpg" ["-s"; "-a"; "-b"; tarball]
    end
;;
