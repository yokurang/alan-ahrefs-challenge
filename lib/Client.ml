open Core
open Async
open Utils
open InputOutputHandlers

let start_client ~host ~port ~stdin_reader_pipe =
  Deferred.ignore_m (
  Monitor.protect (fun () ->
    try_with (fun () ->
      Tcp.with_connection
        (Tcp.Where_to_connect.of_host_and_port { host; port })
        ?timeout:(Some (Time_float_unix.Span.of_sec 5.))
        (fun _sock reader writer ->
          let server_socket_addr = Socket.getpeername _sock in
          let server_socket_addr_str = Socket.Address.to_string server_socket_addr in
          let () = printf "%s has connected.\n%!" server_socket_addr_str in
          let socket_reader_pipe = Reader.pipe reader in
          let socket_writer_pipe = Writer.pipe writer in
          let message_created_at_timestamp_queue : string Queue.t = Queue.create () in
          handle_connection
            ~socket_reader_pipe:socket_reader_pipe
            ~socket_writer_pipe:socket_writer_pipe
            ~stdin_reader_pipe:stdin_reader_pipe
            ~connection_address:server_socket_addr_str
            ~message_created_at_timestamp_queue:message_created_at_timestamp_queue
        ) 
    ) >>= function
    | Ok () ->
      Deferred.return (Pipe.close_read stdin_reader_pipe)
    | Error exn ->
      let%bind () = Deferred.return (Pipe.close_read stdin_reader_pipe) in
      begin match Monitor.extract_exn exn with
      | Unix.Unix_error (Unix.Error.ECONNREFUSED, _, _) ->
        let error_message = Printf.sprintf "Server is not running on %s:%d\n%!" host port in
        let pretty_error_message = pretty_error_message_string error_message in
        let () = print_endline pretty_error_message in
        Shutdown.exit 0
      | exn_message ->
        let pretty_error_message = pretty_error_message_string (Exn.to_string exn_message) in
        let () = print_endline pretty_error_message in
        Shutdown.exit 1
      end
  )
  ~finally:(fun () ->
    let info_message = Printf.sprintf "Closing connection..." in
    let pretty_info_message = pretty_info_message_string info_message in
    let () = print_endline pretty_info_message in
    Deferred.unit
  )
)