-module(oxion_radius_radsec_test_ffi).
-export([probe_local_tls_handshake/4]).

probe_local_tls_handshake(CertPath, KeyPath, CaPath, Timeout)
    when is_binary(CertPath), is_binary(KeyPath), is_binary(CaPath), is_integer(Timeout) ->
    ensure_ssl_started(),
    ListenOptions = [
        {certfile, binary_to_list(CertPath)},
        {keyfile, binary_to_list(KeyPath)},
        {reuseaddr, true},
        {active, false},
        {versions, ['tlsv1.2']}
    ],
    case ssl:listen(0, ListenOptions) of
        {ok, ListenSocket} ->
            try
                {ok, {_Addr, Port}} = ssl:sockname(ListenSocket),
                Parent = self(),
                _AcceptorPid =
                    spawn(fun() ->
                        Parent ! {accept_result, accept_once(ListenSocket, Timeout)}
                    end),
                timer:sleep(20),
                ClientOptions = [
                    {verify, verify_peer},
                    {cacertfile, binary_to_list(CaPath)},
                    {depth, 5},
                    {server_name_indication, "localhost"},
                    {active, false},
                    {versions, ['tlsv1.2']}
                ],
                ClientResult = connect_once(Port, ClientOptions, Timeout),
                AcceptResult = receive_accept_result(Timeout),
                case {ClientResult, AcceptResult} of
                    {ok, ok} ->
                        {ok, nil};
                    {ClientError, AcceptError} ->
                        {error, format_reason({handshake_failed, ClientError, AcceptError})}
                end
            catch
                Class:Reason ->
                    {error, format_reason({Class, Reason})}
            after
                ssl:close(ListenSocket)
            end;
        {error, Reason} ->
            {error, format_reason({listen_failed, Reason})}
    end.

ensure_ssl_started() ->
    _ = application:ensure_all_started(crypto),
    _ = application:ensure_all_started(public_key),
    _ = application:ensure_all_started(ssl),
    ok.

connect_once(Port, ClientOptions, Timeout) ->
    case ssl:connect("127.0.0.1", Port, ClientOptions, Timeout) of
        {ok, ClientSocket} ->
            ssl:close(ClientSocket),
            ok;
        {error, Reason} ->
            {error, {client_connect_failed, Reason}}
    end.

accept_once(ListenSocket, Timeout) ->
    case ssl:transport_accept(ListenSocket, Timeout) of
        {ok, ServerSocket} ->
            try
                case handshake_server_socket(ServerSocket, Timeout) of
                    ok -> ok;
                    {ok, _NegotiatedSocket} -> ok;
                    {error, Reason} -> {error, {server_handshake_failed, Reason}}
                end
            after
                ssl:close(ServerSocket)
            end;
        {error, Reason} ->
            {error, {transport_accept_failed, Reason}}
    end.

handshake_server_socket(ServerSocket, Timeout) ->
    case erlang:function_exported(ssl, handshake, 2) of
        true -> ssl:handshake(ServerSocket, Timeout);
        false ->
            case erlang:function_exported(ssl, handshake, 1) of
                true -> ssl:handshake(ServerSocket);
                false -> {error, unsupported_handshake_api}
            end
    end.

receive_accept_result(Timeout) ->
    receive
        {accept_result, Result} ->
            Result
    after Timeout ->
        {error, accept_timeout}
    end.

format_reason(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
