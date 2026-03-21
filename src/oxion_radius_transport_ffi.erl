-module(oxion_radius_transport_ffi).
-export([
    md5/1,
    hmac_md5/2,
    send_and_receive/4,
    open_reusable_udp_socket/2,
    send_and_receive_with_socket/5,
    close_reusable_udp_socket/1
]).

-define(SOCKET_TABLE, oxion_radius_transport_socket_table).

md5(Input) when is_binary(Input) ->
    crypto:hash(md5, Input).

hmac_md5(Secret, Input) when is_binary(Secret), is_binary(Input) ->
    crypto:mac(hmac, md5, Secret, Input).

send_and_receive(Host, Port, Payload, Timeout) when is_binary(Host), is_integer(Port), is_binary(Payload), is_integer(Timeout) ->
    case inet:parse_address(binary_to_list(Host)) of
        {ok, IpAddress} ->
            case gen_udp:open(0, [binary, {active, false}]) of
                {ok, Socket} ->
                    try
                        case gen_udp:send(Socket, IpAddress, Port, Payload) of
                            ok ->
                                case gen_udp:recv(Socket, 0, Timeout) of
                                    {ok, {_RecvIp, _RecvPort, Response}} -> {ok, Response};
                                    {error, timeout} -> {error, <<"timeout">>};
                                    {error, Reason} -> {error, format_reason(Reason)}
                                end;
                            {error, Reason} ->
                                {error, format_reason(Reason)}
                        end
                    after
                        gen_udp:close(Socket)
                    end;
                {error, Reason} ->
                    {error, format_reason(Reason)}
            end;
        {error, Reason} ->
            {error, format_reason(Reason)}
    end.

open_reusable_udp_socket(LocalBind, ReuseSocket) when is_binary(LocalBind), is_boolean(ReuseSocket) ->
    ensure_socket_table(),
    case inet:parse_address(binary_to_list(LocalBind)) of
        {ok, BindAddress} ->
            case gen_udp:open(0, [binary, {active, false}, {ip, BindAddress}, {reuseaddr, ReuseSocket}]) of
                {ok, Socket} ->
                    Handle = erlang:unique_integer([positive, monotonic]),
                    true = ets:insert(?SOCKET_TABLE, {Handle, Socket}),
                    {ok, Handle};
                {error, Reason} ->
                    {error, format_reason(Reason)}
            end;
        {error, Reason} ->
            {error, format_reason(Reason)}
    end.

send_and_receive_with_socket(Handle, Host, Port, Payload, Timeout)
    when is_integer(Handle), is_binary(Host), is_integer(Port), is_binary(Payload), is_integer(Timeout) ->
    ensure_socket_table(),
    case ets:lookup(?SOCKET_TABLE, Handle) of
        [{Handle, Socket}] ->
            case inet:parse_address(binary_to_list(Host)) of
                {ok, IpAddress} ->
                    case gen_udp:send(Socket, IpAddress, Port, Payload) of
                        ok ->
                            case gen_udp:recv(Socket, 0, Timeout) of
                                {ok, {_RecvIp, _RecvPort, Response}} -> {ok, Response};
                                {error, timeout} -> {error, <<"timeout">>};
                                {error, Reason} -> {error, format_reason(Reason)}
                            end;
                        {error, Reason} ->
                            {error, format_reason(Reason)}
                    end;
                {error, Reason} ->
                    {error, format_reason(Reason)}
            end;
        [] ->
            {error, <<"socket_handle_not_found">>}
    end.

close_reusable_udp_socket(Handle) when is_integer(Handle) ->
    ensure_socket_table(),
    case ets:take(?SOCKET_TABLE, Handle) of
        [{Handle, Socket}] ->
            gen_udp:close(Socket),
            nil;
        [] ->
            nil
    end.

ensure_socket_table() ->
    case ets:info(?SOCKET_TABLE) of
        undefined ->
            ets:new(?SOCKET_TABLE, [named_table, public, set]),
            ok;
        _ ->
            ok
    end.

format_reason(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
