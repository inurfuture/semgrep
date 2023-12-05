(* Martin Jambon
 *
 * Copyright (C) 2023 Semgrep Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * LICENSE for more details.
 *)
open Fpath_.Operators

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
   Operations on files in the general sense (regular file, folder, etc.).

   For now, this is a thin layer on top of Common. Eventually, we want
   to get rid of the interface exposed by Common.

   related libraries:
    - Bos.OS.File, Bos.OS.Dir, Bos.OS.Path, which we should probably use
     (ex: https://erratique.ch/software/bos/doc/Bos/OS/Dir/index.html )
*)

(*****************************************************************************)
(* API *)
(*****************************************************************************)

let fullpath file = UCommon.fullpath !!file |> Fpath.v

let files_of_dirs_or_files_no_vcs_nofilter xs =
  xs |> Fpath_.to_strings |> UCommon.files_of_dir_or_files_no_vcs_nofilter
  |> Fpath_.of_strings

let cat path = UCommon.cat !!path
let write_file path data = UCommon.write_file !!path data
let read_file ?max_len path = UCommon.read_file ?max_len !!path
let with_open_out path func = UCommon.with_open_outfile !!path func
let with_open_in path func = UCommon.with_open_infile !!path func
let new_temp_file prefix suffix = UCommon.new_temp_file prefix suffix |> Fpath.v
let erase_temp_files = UCommon.erase_temp_files
let erase_this_temp_file path = UCommon.erase_this_temp_file !!path
let is_executable path = Common2.is_executable !!path
let filesize path = Common2.filesize !!path

let find_first_match_with_whole_line path ?split:(chr = '\n') =
  Bos.OS.File.with_ic path @@ fun ic term ->
  let len = in_channel_length ic in
  let res = Bytes.create len in
  really_input ic res 0 len;
  let lines = Bytes.split_on_char chr res in
  let lines = List_.map Bytes.unsafe_to_string lines in
  lines |> List.find_opt (fun str -> String_.contains ~term str)

let find_first_match_with_whole_line path ?split term =
  find_first_match_with_whole_line path ?split term
  |> Result.to_option |> Option.join

let filemtime file = (UUnix.stat !!file).st_mtime

(* TODO? slow, and maybe we should cache it to avoid rereading
 * each time the same file for each match.
 * Note that the returned lines do not contain \n.
 *)
let lines_of_file (start_line, end_line) file : string list =
  let arr = Common2.cat_array (Fpath.to_string file) in
  let lines = Common2.enum start_line end_line in
  lines |> List_.map (fun i -> arr.(i))

let replace_named_pipe_by_regular_file_if_needed ?(prefix = "named-pipe")
    (path : Fpath.t) : Fpath.t =
  if !Common.jsoo then path
    (* don't bother supporting exotic things like fds if running in JS *)
  else
    match (UUnix.stat !!path).st_kind with
    | Unix.S_FIFO ->
        let data = read_file path in
        let suffix = "-" ^ Fpath.basename path in
        let tmp_path, oc =
          UFilename.open_temp_file
            ~mode:[ Open_creat; Open_excl; Open_wronly; Open_binary ]
            prefix suffix
        in
        let remove () =
          if USys.file_exists tmp_path then USys.remove tmp_path
        in
        (* Try to remove temporary file when program exits. *)
        UStdlib.at_exit remove;
        Common.protect
          ~finally:(fun () -> close_out_noerr oc)
          (fun () -> output_string oc data);
        Fpath.v tmp_path
    | _ -> path