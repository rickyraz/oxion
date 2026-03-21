import gleam/int
import gleam/option
import oxion/radius/coa/transport as shared_transport
import oxion/radius/disconnect/request
import oxion/radius/disconnect/response
import oxion/radius/packet

pub type PreparedRoundtrip {
  PreparedRoundtrip(
    identifier: Int,
    request_authenticator: BitArray,
    payload: BitArray,
  )
}

@external(erlang, "oxion_radius_transport_ffi", "send_and_receive")
fn send_and_receive(
  host: String,
  port: Int,
  payload: BitArray,
  timeout_ms: Int,
) -> Result(BitArray, String)

pub fn prepare_roundtrip(
  request_value: request.DisconnectRequest,
  config: shared_transport.CoaTransportConfig,
) -> Result(PreparedRoundtrip, String) {
  let shared_transport.CoaTransportConfig(
    host: _host,
    port: _port,
    secret: secret,
    timeout_ms: _timeout_ms,
    request_security: request_security,
    require_message_authenticator_response: _require_message_authenticator_response,
  ) = config

  // Why: Disconnect needs the same prepared-request seam as CoA so replay,
  // auditing, and live execution can reason about one packet instance before
  // any network I/O happens.
  case
    packet.encode_disconnect_request_with_security(
      request_value,
      secret,
      request_security,
    )
  {
    Error(error) -> Error(packet_error_reason(error))
    Ok(packet.EncodedRequest(
      identifier: identifier,
      request_authenticator: request_authenticator,
      payload: payload,
    )) ->
      Ok(PreparedRoundtrip(
        identifier: identifier,
        request_authenticator: request_authenticator,
        payload: payload,
      ))
  }
}

pub fn roundtrip(
  request_value: request.DisconnectRequest,
  config: shared_transport.CoaTransportConfig,
) -> response.DisconnectResponse {
  case prepare_roundtrip(request_value, config) {
    Error(reason) ->
      response.TransportError(reason: "packet_prepare_failed:" <> reason)
    Ok(prepared) -> roundtrip_prepared(prepared, config)
  }
}

pub fn roundtrip_prepared(
  prepared: PreparedRoundtrip,
  config: shared_transport.CoaTransportConfig,
) -> response.DisconnectResponse {
  let shared_transport.CoaTransportConfig(
    host: host,
    port: port,
    secret: secret,
    timeout_ms: timeout_ms,
    request_security: _request_security,
    require_message_authenticator_response: require_message_authenticator_response,
  ) = config
  let PreparedRoundtrip(
    identifier: identifier,
    request_authenticator: request_authenticator,
    payload: payload,
  ) = prepared

  case send_and_receive(host, port, payload, timeout_ms) {
    Error(reason) -> map_transport_error(reason)
    Ok(raw_response) ->
      case packet.decode_packet(raw_response) {
        Error(error) -> response.Malformed(reason: packet_error_reason(error))
        Ok(response_packet) ->
          case packet.ensure_identifier(response_packet, identifier) {
            Error(error) ->
              response.Malformed(reason: packet_error_reason(error))
            Ok(_) ->
              case
                packet.verify_response_security(
                  response_packet,
                  request_authenticator,
                  secret,
                  require_message_authenticator_response,
                )
              {
                Error(error) ->
                  response.Malformed(reason: packet_error_reason(error))
                Ok(_) -> map_packet_to_response(response_packet, host)
              }
          }
      }
  }
}

fn map_packet_to_response(
  response_packet: packet.RadiusPacket,
  nas: String,
) -> response.DisconnectResponse {
  let packet.RadiusPacket(
    code: code,
    identifier: _identifier,
    length: _length,
    authenticator: _authenticator,
    attributes: attributes,
  ) = response_packet

  case code {
    packet.DisconnectAckCode -> response.Ack(nas: nas)
    packet.DisconnectNakCode ->
      response.Nak(
        nas: nas,
        error_code: nak_code(attributes),
        error_message: nak_message(attributes),
      )
    packet.DisconnectRequestCode ->
      response.Malformed(reason: "unexpected_request_packet_received")
    packet.CoaRequestCode | packet.CoaAckCode | packet.CoaNakCode ->
      response.Malformed(reason: "unexpected_coa_packet_received")
  }
}

fn nak_code(attributes: List(packet.RadiusAttribute)) -> String {
  case packet.error_cause(attributes) {
    option.Some(code) -> "error_cause_" <> int.to_string(code)
    option.None -> "disconnect_nak"
  }
}

fn nak_message(attributes: List(packet.RadiusAttribute)) -> String {
  case packet.reply_message(attributes) {
    option.Some(message) -> message
    option.None -> "disconnect_request_rejected"
  }
}

fn map_transport_error(reason: String) -> response.DisconnectResponse {
  case reason {
    "timeout" -> response.Timeout
    _ -> response.TransportError(reason: reason)
  }
}

fn packet_error_reason(error: packet.PacketError) -> String {
  case error {
    packet.InvalidCode(code) -> "invalid_code:" <> int.to_string(code)
    packet.PacketTooShort -> "packet_too_short"
    packet.InvalidPacketLength(length) ->
      "invalid_packet_length:" <> int.to_string(length)
    packet.InvalidAuthenticatorLength -> "invalid_authenticator_length"
    packet.InvalidAttributeLength(type_id, length) ->
      "invalid_attribute_length:"
      <> int.to_string(type_id)
      <> ":"
      <> int.to_string(length)
    packet.InvalidIpAddress(value) -> "invalid_ip_address:" <> value
    packet.InvalidAttributeValue(reason) -> "invalid_attribute_value:" <> reason
    packet.UnsupportedLiveAttribute(name) ->
      "unsupported_live_attribute:" <> name
    packet.UnsupportedLiveVendor(vendor) -> "unsupported_live_vendor:" <> vendor
    packet.MissingMessageAuthenticator -> "missing_message_authenticator"
    packet.MessageAuthenticatorMismatch -> "message_authenticator_mismatch"
    packet.ResponseAuthenticatorMismatch -> "response_authenticator_mismatch"
    packet.UnexpectedIdentifier(expected, actual) ->
      "unexpected_identifier:"
      <> int.to_string(expected)
      <> ":"
      <> int.to_string(actual)
  }
}
