import gleam/int
import gleam/option
import oxion/radius/packet
import oxion/radius/registry/types

pub type StatusPort {
  AuthenticationPort
  AccountingPort
}

pub type StatusRequest {
  StatusRequest(
    endpoint_id: String,
    port: StatusPort,
    requires_message_authenticator: Bool,
  )
}

pub type StatusResult {
  Reachable(response_kind: String)
  Unreachable(reason: String)
}

pub type StatusBuildError {
  StatusUnsupported(endpoint_id: String)
}

pub type StatusTransportConfig {
  StatusTransportConfig(
    host: String,
    port: Int,
    secret: String,
    timeout_ms: Int,
    require_message_authenticator_response: Bool,
  )
}

@external(erlang, "oxion_radius_transport_ffi", "send_and_receive")
fn send_and_receive(
  host: String,
  port: Int,
  payload: BitArray,
  timeout_ms: Int,
) -> Result(BitArray, String)

pub fn build_request(
  endpoint: types.NasEndpoint,
  port: StatusPort,
) -> Result(StatusRequest, StatusBuildError) {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: capabilities,
  ) = endpoint
  let types.NasCapabilities(
    supports_coa: _supports_coa,
    supports_disconnect: _supports_disconnect,
    supports_status_server: supports_status_server,
    requires_message_authenticator: requires_message_authenticator,
    requires_event_timestamp: _requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  case supports_status_server {
    True ->
      Ok(StatusRequest(
        endpoint_id: endpoint_id,
        port: port,
        requires_message_authenticator: requires_message_authenticator,
      ))
    False -> Error(StatusUnsupported(endpoint_id: endpoint_id))
  }
}

pub fn from_endpoint(
  endpoint: types.NasEndpoint,
  secret: String,
  port: StatusPort,
) -> StatusTransportConfig {
  let types.NasEndpoint(
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
  let types.NasCapabilities(
    supports_coa: _supports_coa,
    supports_disconnect: _supports_disconnect,
    supports_status_server: _supports_status_server,
    requires_message_authenticator: requires_message_authenticator,
    requires_event_timestamp: _requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  // Why: the endpoint model does not yet distinguish auth/accounting/status
  // sockets, so ops tooling reuses the adapter-bound host/port fields as an
  // explicit smoke path until endpoint inventory grows a richer status target.
  StatusTransportConfig(
    host: coa_host,
    port: case port {
      AuthenticationPort -> coa_port
      AccountingPort -> coa_port
    },
    secret: secret,
    timeout_ms: timeout_ms,
    require_message_authenticator_response: requires_message_authenticator,
  )
}

pub fn roundtrip(
  request: StatusRequest,
  config: StatusTransportConfig,
) -> StatusResult {
  let StatusRequest(
    endpoint_id: endpoint_id,
    port: port,
    requires_message_authenticator: requires_message_authenticator,
  ) = request
  let StatusTransportConfig(
    host: host,
    port: target_port,
    secret: secret,
    timeout_ms: timeout_ms,
    require_message_authenticator_response: require_message_authenticator_response,
  ) = config

  case
    packet.encode_status_request_with_security(
      endpoint_id <> ":" <> port_to_fingerprint(port),
      secret,
      packet.PacketSecurityConfig(
        message_authenticator: requires_message_authenticator,
        event_timestamp: option.None,
      ),
    )
  {
    Error(error) ->
      Unreachable(
        reason: "packet_prepare_failed:" <> packet_error_reason(error),
      )
    Ok(packet.EncodedRequest(
      identifier: identifier,
      request_authenticator: request_authenticator,
      payload: payload,
    )) ->
      case send_and_receive(host, target_port, payload, timeout_ms) {
        Error(reason) -> map_transport_error(reason)
        Ok(raw_response) ->
          case packet.decode_packet(raw_response) {
            Error(error) ->
              Unreachable(
                reason: "malformed_response:" <> packet_error_reason(error),
              )
            Ok(response_packet) ->
              case packet.ensure_identifier(response_packet, identifier) {
                Error(error) ->
                  Unreachable(
                    reason: "malformed_response:" <> packet_error_reason(error),
                  )
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
                      Unreachable(
                        reason: "malformed_response:"
                        <> packet_error_reason(error),
                      )
                    Ok(_) -> map_response(response_packet)
                  }
              }
          }
      }
  }
}

fn map_response(packet_value: packet.RadiusPacket) -> StatusResult {
  let packet.RadiusPacket(
    code: code,
    identifier: _identifier,
    length: _length,
    authenticator: _authenticator,
    attributes: _attributes,
  ) = packet_value

  case code {
    packet.AccessAcceptCode -> Reachable(response_kind: "access_accept")
    packet.AccessRejectCode -> Reachable(response_kind: "access_reject")
    packet.AccountingResponseCode ->
      Reachable(response_kind: "accounting_response")
    packet.StatusServerCode ->
      Reachable(response_kind: "status_server_response")
    packet.CoaRequestCode
    | packet.CoaAckCode
    | packet.CoaNakCode
    | packet.DisconnectRequestCode
    | packet.DisconnectAckCode
    | packet.DisconnectNakCode ->
      Unreachable(reason: "unexpected_dynamic_authorization_packet")
  }
}

fn map_transport_error(reason: String) -> StatusResult {
  case reason {
    "timeout" -> Unreachable(reason: "timeout")
    _ -> Unreachable(reason: reason)
  }
}

fn port_to_fingerprint(port: StatusPort) -> String {
  case port {
    AuthenticationPort -> "auth"
    AccountingPort -> "acct"
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
