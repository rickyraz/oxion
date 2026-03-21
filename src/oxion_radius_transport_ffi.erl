-module(oxion_radius_transport_ffi).
-export([md5/1, hmac_md5/2, send_and_receive/4]).

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

format_reason(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
