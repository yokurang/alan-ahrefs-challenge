open Core
open Async
open Utils
open InputOutputHandlers

(** Function to start the server *)
let start_server ~port ~stdin_reader_pipe =
  Deferred.ignore_m (
    Monitor.protect (fun () ->
      let greeting_phrases : string list = [
      "Do you want to make the first move.......?"; "A good joke is a great conversation starter!";
      "Love is in the air!"; "Maybe ask them to go hiking together?"
      ] in
      let header = sprintf "\n|| Server Startup Information ||\n" in
      let info_message = sprintf "Server has started on port %d. Awaiting connections..." port in
      let pretty_info_message = pretty_info_message_string info_message in
      let start_up_message = sprintf "%s\n%s" header pretty_info_message in
      print_endline start_up_message;
      try_with (fun () ->
        Tcp.Server.create
          ~on_handler_error:`Raise
          ~max_connections:1
          (Tcp.Where_to_listen.of_port port)
          (fun _addr reader writer ->
            let client_socket_addr_str = Socket.Address.to_string _addr in
            let  greeting_phrase = List.random_element_exn greeting_phrases in
            let () = print_endline (pretty_info_message_string
            (sprintf "Client %s has connected to the server. %s"
            client_socket_addr_str greeting_phrase)) in
            let socket_reader_pipe = Reader.pipe reader in
            let socket_writer_pipe = Writer.pipe writer in
            handle_connection
              ~socket_reader_pipe:socket_reader_pipe
              ~socket_writer_pipe:socket_writer_pipe
              ~stdin_reader_pipe:stdin_reader_pipe
              ~connection_address:client_socket_addr_str
          )
      ) >>= function
      | Ok _ -> 
        Deferred.never ()
      | Error exn ->
        let%bind () = Deferred.return (Pipe.close_read stdin_reader_pipe) in
        begin match Monitor.extract_exn exn with
        | Unix.Unix_error (Unix.Error.EADDRNOTAVAIL, _, _) ->
          let error_message = Printf.sprintf "Port %d is not available.\n%!" port in
          let pretty_error_message = pretty_error_message_string error_message in
          let () = print_endline pretty_error_message in
          Shutdown.exit 0
        | Unix.Unix_error (Unix.Error.EADDRINUSE, _, _) ->
          let error_message = Printf.sprintf "Port %d is already in use.\n%!" port in
          let pretty_error_message = pretty_error_message_string error_message in
          let () = print_endline pretty_error_message in
          Shutdown.exit 0
        | Unix.Unix_error (Unix.Error.EACCES, _, _) ->
          let error_message = Printf.sprintf "Port %d is not accessible.\n%!" port in
          let pretty_error_message = pretty_error_message_string error_message in
          let () = print_endline pretty_error_message in
          Shutdown.exit 0
        | exn_message ->
          let pretty_error_message = (Exn.to_string exn_message) in 
          let () = print_endline pretty_error_message in
          Shutdown.exit 1
        end
    )
    ~finally:(fun () ->
      let info_message = Printf.sprintf "Shutting down..." in
      let pretty_info_message = pretty_info_message_string info_message in
      let () = print_endline pretty_info_message in
      Deferred.unit
    )
  )
