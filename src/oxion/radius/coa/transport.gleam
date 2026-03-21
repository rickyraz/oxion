import gleam/int
import gleam/option
import oxion/radius/coa/request
import oxion/radius/coa/response
import oxion/radius/packet
import oxion/radius/registry/types as registry_types
import oxion/radius/vendor/types as vendor_types

pub type CoaTransportConfig {
  CoaTransportConfig(
    host: String,
    port: Int,
    secret: String,
    timeout_ms: Int,
    request_security: packet.PacketSecurityConfig,
    require_message_authenticator_response: Bool,
  )
}

pub type PreparedRoundtrip {
  PreparedRoundtrip(
    identifier: Int,
    request_authenticator: BitArray,
    event_timestamp: option.Option(Int),
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

pub fn from_endpoint(
  endpoint: registry_types.NasEndpoint,
  secret: String,
  now_seconds: Int,
) -> CoaTransportConfig {
  let registry_types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: _endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: coa_host,
    coa_port: coa_port,
    secret_ref: _secret_ref,
    timeout_ms: timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: capabilities,
  ) = endpoint
  let registry_types.NasCapabilities(
    supports_coa: _supports_coa,
    supports_disconnect: _supports_disconnect,
    supports_status_server: _supports_status_server,
    requires_message_authenticator: requires_message_authenticator,
    requires_event_timestamp: requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  // Why: endpoint capabilities must drive packet hardening so the live path
  // stops relying on ad-hoc caller decisions about message integrity settings.
  CoaTransportConfig(
    host: coa_host,
    port: coa_port,
    secret: secret,
    timeout_ms: timeout_ms,
    request_security: packet.PacketSecurityConfig(
      message_authenticator: requires_message_authenticator,
      event_timestamp: case requires_event_timestamp {
        True -> option.Some(now_seconds)
        False -> option.None
      },
    ),
    require_message_authenticator_response: requires_message_authenticator,
  )
}

pub fn roundtrip(
  request_value: request.CoaRequest,
  vendor: vendor_types.RadiusVendor,
  target_id: String,
  config: CoaTransportConfig,
) -> response.CoaResponse {
  case prepare_roundtrip(request_value, vendor, config) {
    Error(reason) ->
      response.TransportError(reason: "packet_prepare_failed:" <> reason)
    Ok(prepared) -> roundtrip_prepared(prepared, target_id, config)
  }
}

pub fn prepare_roundtrip(
  request_value: request.CoaRequest,
  vendor: vendor_types.RadiusVendor,
  config: CoaTransportConfig,
) -> Result(PreparedRoundtrip, String) {
  let CoaTransportConfig(
    secret: secret,
    request_security: request_security,
    host: _host,
    port: _port,
    timeout_ms: _timeout_ms,
    require_message_authenticator_response: _require_message_authenticator_response,
  ) = config
  let packet.PacketSecurityConfig(
    message_authenticator: _message_authenticator,
    event_timestamp: event_timestamp,
  ) = request_security

  case
    packet.encode_coa_request_with_security(
      request_value,
      vendor,
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
        event_timestamp: event_timestamp,
        payload: payload,
      ))
  }
}

pub fn roundtrip_prepared(
  prepared: PreparedRoundtrip,
  target_id: String,
  config: CoaTransportConfig,
) -> response.CoaResponse {
  let CoaTransportConfig(
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
    event_timestamp: _event_timestamp,
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
                Ok(_) ->
                  map_packet_to_response(response_packet, host, target_id)
              }
          }
      }
  }
}

fn map_packet_to_response(
  response_packet: packet.RadiusPacket,
  nas: String,
  target_id: String,
) -> response.CoaResponse {
  let packet.RadiusPacket(
    code: code,
    identifier: _identifier,
    length: _length,
    authenticator: _authenticator,
    attributes: attributes,
  ) = response_packet

  case code {
    packet.CoaAckCode -> response.Ack(nas: nas, applied_target: target_id)
    packet.CoaNakCode ->
      response.Nak(
        nas: nas,
        error_code: nak_code(attributes),
        error_message: nak_message(attributes),
      )
    packet.CoaRequestCode | packet.DisconnectRequestCode ->
      response.Malformed(reason: "unexpected_request_packet_received")
    packet.DisconnectAckCode | packet.DisconnectNakCode ->
      response.Malformed(reason: "unexpected_disconnect_packet_received")
  }
}

fn nak_code(attributes: List(packet.RadiusAttribute)) -> String {
  case packet.error_cause(attributes) {
    option.Some(code) -> "error_cause_" <> int.to_string(code)
    option.None -> "coa_nak"
  }
}

fn nak_message(attributes: List(packet.RadiusAttribute)) -> String {
  case packet.reply_message(attributes) {
    option.Some(message) -> message
    option.None -> "coa_request_rejected"
  }
}

fn map_transport_error(reason: String) -> response.CoaResponse {
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
