import gleam/int
import gleam/option
import oxion/radius/coa/request
import oxion/radius/coa/response
import oxion/radius/packet
import oxion/radius/vendor/types as vendor_types

pub type CoaTransportConfig {
  CoaTransportConfig(host: String, port: Int, secret: String, timeout_ms: Int)
}

@external(erlang, "oxion_radius_transport_ffi", "send_and_receive")
fn send_and_receive(
  host: String,
  port: Int,
  payload: BitArray,
  timeout_ms: Int,
) -> Result(BitArray, String)

pub fn roundtrip(
  request_value: request.CoaRequest,
  vendor: vendor_types.RadiusVendor,
  target_id: String,
  config: CoaTransportConfig,
) -> response.CoaResponse {
  let CoaTransportConfig(
    host: host,
    port: port,
    secret: secret,
    timeout_ms: timeout_ms,
  ) = config

  case packet.encode_coa_request(request_value, vendor, secret) {
    Error(error) -> response.TransportError(reason: packet_error_reason(error))
    Ok(packet.EncodedRequest(
      identifier: identifier,
      request_authenticator: request_authenticator,
      payload: payload,
    )) ->
      case send_and_receive(host, port, payload, timeout_ms) {
        Error(reason) -> map_transport_error(reason)
        Ok(raw_response) ->
          case packet.decode_packet(raw_response) {
            Error(error) ->
              response.Malformed(reason: packet_error_reason(error))
            Ok(response_packet) ->
              case packet.ensure_identifier(response_packet, identifier) {
                Error(error) ->
                  response.Malformed(reason: packet_error_reason(error))
                Ok(_) ->
                  case
                    packet.verify_response_authenticator(
                      response_packet,
                      request_authenticator,
                      secret,
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
    packet.CoaRequestCode ->
      response.Malformed(reason: "unexpected_request_packet_received")
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
    packet.ResponseAuthenticatorMismatch -> "response_authenticator_mismatch"
    packet.UnexpectedIdentifier(expected, actual) ->
      "unexpected_identifier:"
      <> int.to_string(expected)
      <> ":"
      <> int.to_string(actual)
  }
}
