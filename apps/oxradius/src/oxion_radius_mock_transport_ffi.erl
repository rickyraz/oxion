-module(oxion_radius_mock_transport_ffi).
-export([start_ack_server/1, start_nak_server/3, start_bad_auth_server/1, start_echo_server/0, start_status_server/1]).

start_ack_server(Secret) when is_binary(Secret) ->
    start_server(Secret, ack).

start_nak_server(Secret, ErrorCause, Message) when is_binary(Secret), is_integer(ErrorCause), is_binary(Message) ->
    start_server(Secret, {nak, ErrorCause, Message}).

start_bad_auth_server(Secret) when is_binary(Secret) ->
    start_server(Secret, bad_auth).

start_echo_server() ->
    start_server(<<>>, echo).

start_status_server(Secret) when is_binary(Secret) ->
    start_server(Secret, status).

start_server(Secret, Mode) ->
    case gen_udp:open(0, [binary, {active, false}, {reuseaddr, true}]) of
        {ok, Socket} ->
            {ok, {_Addr, Port}} = inet:sockname(Socket),
            spawn(fun() -> serve_once(Socket, Secret, Mode) end),
            {ok, Port};
        {error, Reason} ->
            {error, format_reason(Reason)}
    end.

serve_once(Socket, Secret, Mode) ->
    case gen_udp:recv(Socket, 0, 3000) of
        {ok, {ClientIp, ClientPort, Packet}} ->
            Reply =
                case Mode of
                    echo -> Packet;
                    _ -> build_reply(Packet, Secret, Mode)
                end,
            _ = gen_udp:send(Socket, ClientIp, ClientPort, Reply),
            gen_udp:close(Socket);
        {error, _Reason} ->
            gen_udp:close(Socket)
    end.

build_reply(<<RequestCode, Identifier, _Length:16, RequestAuthenticator:16/binary, _/binary>>, Secret, Mode) ->
    {AckCode, NakCode} = reply_codes(RequestCode),
    {ReplyCode, Attributes, Authenticator} =
        case Mode of
            ack ->
                Attrs = with_message_authenticator(AckCode, Identifier, RequestAuthenticator, <<>>, Secret),
                {AckCode, Attrs, response_authenticator(AckCode, Identifier, RequestAuthenticator, Attrs, Secret)};
            status ->
                StatusCode = 2,
                Attrs = with_message_authenticator(StatusCode, Identifier, RequestAuthenticator, <<>>, Secret),
                {StatusCode, Attrs, response_authenticator(StatusCode, Identifier, RequestAuthenticator, Attrs, Secret)};
            {nak, ErrorCause, Message} ->
                Attrs0 = <<101, 6, ErrorCause:32, 18, (byte_size(Message) + 2), Message/binary>>,
                Attrs = with_message_authenticator(NakCode, Identifier, RequestAuthenticator, Attrs0, Secret),
                {NakCode, Attrs, response_authenticator(NakCode, Identifier, RequestAuthenticator, Attrs, Secret)};
            bad_auth ->
                Attrs = <<>>,
                {AckCode, Attrs, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
        end,
    Length = 20 + byte_size(Attributes),
    <<ReplyCode, Identifier, Length:16, Authenticator/binary, Attributes/binary>>.

reply_codes(40) -> {41, 42};
reply_codes(_) -> {44, 45}.

response_authenticator(Code, Identifier, RequestAuthenticator, Attributes, Secret) ->
    Length = 20 + byte_size(Attributes),
    crypto:hash(md5, <<Code, Identifier, Length:16, RequestAuthenticator/binary, Attributes/binary, Secret/binary>>).

with_message_authenticator(Code, Identifier, RequestAuthenticator, Attributes, Secret) ->
    Placeholder = <<Attributes/binary, 80, 18, 0:128>>,
    Length = 20 + byte_size(Placeholder),
    MessageAuthenticator =
        crypto:mac(
            hmac,
            md5,
            Secret,
            <<Code, Identifier, Length:16, RequestAuthenticator/binary, Placeholder/binary>>
        ),
    <<Attributes/binary, 80, 18, MessageAuthenticator/binary>>.

format_reason(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
