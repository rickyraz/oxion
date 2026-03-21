import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import oxion/radius/coa/request
import oxion/radius/profile/snapshot
import oxion/radius/vendor/types as vendor_types

pub type RadiusCode {
  DisconnectRequestCode
  DisconnectAckCode
  DisconnectNakCode
  CoaRequestCode
  CoaAckCode
  CoaNakCode
}

pub type RadiusAttribute {
  RadiusAttribute(type_id: Int, value: BitArray)
}

pub type RadiusPacket {
  RadiusPacket(
    code: RadiusCode,
    identifier: Int,
    length: Int,
    authenticator: BitArray,
    attributes: List(RadiusAttribute),
  )
}

pub type PacketError {
  InvalidCode(code: Int)
  PacketTooShort
  InvalidPacketLength(length: Int)
  InvalidAuthenticatorLength
  InvalidAttributeLength(type_id: Int, length: Int)
  InvalidIpAddress(value: String)
  InvalidAttributeValue(reason: String)
  UnsupportedLiveAttribute(name: String)
  UnsupportedLiveVendor(vendor: String)
  ResponseAuthenticatorMismatch
  UnexpectedIdentifier(expected: Int, actual: Int)
}

pub type EncodedRequest {
  EncodedRequest(
    identifier: Int,
    request_authenticator: BitArray,
    payload: BitArray,
  )
}

@external(erlang, "oxion_radius_transport_ffi", "md5")
fn md5(input: BitArray) -> BitArray

pub fn identifier_from_fingerprint(fingerprint: String) -> Int {
  let digest = md5(bit_array.from_string(fingerprint))

  case digest {
    <<first, _rest:bytes>> -> first
    _ -> 0
  }
}

pub fn encode_coa_request(
  request_value: request.CoaRequest,
  vendor: vendor_types.RadiusVendor,
  secret: String,
) -> Result(EncodedRequest, PacketError) {
  let request.CoaRequest(
    packet_type: _packet_type,
    reason: _reason,
    action_fingerprint: action_fingerprint,
    session_selector: selector,
    attributes: attributes,
    disconnect_hint: _disconnect_hint,
  ) = request_value

  let identifier = identifier_from_fingerprint(action_fingerprint)

  use selector_attributes <- result.try(selector_to_attributes(selector))
  use request_attributes <- result.try(
    named_attributes_to_radius(attributes, vendor, []),
  )

  let all_attributes = list.append(selector_attributes, request_attributes)
  let attributes_bits = encode_attributes(all_attributes, [])
  let length = 20 + bit_array.byte_size(attributes_bits)
  let zero_authenticator = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
  let secret_bits = bit_array.from_string(secret)
  let authenticator =
    md5(<<
      43,
      identifier,
      length:16,
      zero_authenticator:bits,
      attributes_bits:bits,
      secret_bits:bits,
    >>)
  let payload = <<
    43,
    identifier,
    length:16,
    authenticator:bits,
    attributes_bits:bits,
  >>

  Ok(EncodedRequest(
    identifier: identifier,
    request_authenticator: authenticator,
    payload: payload,
  ))
}

pub fn decode_packet(payload: BitArray) -> Result(RadiusPacket, PacketError) {
  case bit_array.byte_size(payload) < 20 {
    True -> Error(PacketTooShort)
    False -> {
      use code_int <- result.try(byte_at(payload, 0))
      use identifier <- result.try(byte_at(payload, 1))
      use length <- result.try(uint16_at(payload, 2))

      case length < 20 || length > bit_array.byte_size(payload) {
        True -> Error(InvalidPacketLength(length: length))
        False -> {
          use authenticator <- result.try(slice(payload, 4, 16))
          use attributes_bits <- result.try(slice(payload, 20, length - 20))
          use attributes <- result.try(decode_attributes(attributes_bits, []))
          use code <- result.try(radius_code_from_int(code_int))

          Ok(RadiusPacket(
            code: code,
            identifier: identifier,
            length: length,
            authenticator: authenticator,
            attributes: attributes,
          ))
        }
      }
    }
  }
}

pub fn verify_response_authenticator(
  packet: RadiusPacket,
  request_authenticator: BitArray,
  secret: String,
) -> Result(Nil, PacketError) {
  let RadiusPacket(
    code: code,
    identifier: identifier,
    length: length,
    authenticator: authenticator,
    attributes: attributes,
  ) = packet

  case bit_array.byte_size(authenticator) == 16 {
    False -> Error(InvalidAuthenticatorLength)
    True -> {
      let attributes_bits = encode_attributes(attributes, [])
      let secret_bits = bit_array.from_string(secret)
      let expected =
        md5(<<
          radius_code_to_int(code),
          identifier,
          length:16,
          request_authenticator:bits,
          attributes_bits:bits,
          secret_bits:bits,
        >>)

      case expected == authenticator {
        True -> Ok(Nil)
        False -> Error(ResponseAuthenticatorMismatch)
      }
    }
  }
}

pub fn ensure_identifier(
  packet: RadiusPacket,
  expected_identifier: Int,
) -> Result(Nil, PacketError) {
  let RadiusPacket(
    code: _code,
    identifier: identifier,
    length: _length,
    authenticator: _authenticator,
    attributes: _attributes,
  ) = packet

  case identifier == expected_identifier {
    True -> Ok(Nil)
    False ->
      Error(UnexpectedIdentifier(
        expected: expected_identifier,
        actual: identifier,
      ))
  }
}

pub fn error_cause(attributes: List(RadiusAttribute)) -> option.Option(Int) {
  error_cause_loop(attributes)
}

fn error_cause_loop(attributes: List(RadiusAttribute)) -> option.Option(Int) {
  case attributes {
    [] -> option.None
    [RadiusAttribute(type_id: 101, value: value), ..rest] ->
      case value {
        <<cause:32>> -> option.Some(cause)
        _ -> error_cause_loop(rest)
      }
    [_, ..rest] -> error_cause_loop(rest)
  }
}

pub fn reply_message(attributes: List(RadiusAttribute)) -> option.Option(String) {
  reply_message_loop(attributes)
}

pub fn event_timestamp(attributes: List(RadiusAttribute)) -> option.Option(Int) {
  event_timestamp_loop(attributes)
}

pub fn message_authenticator(
  attributes: List(RadiusAttribute),
) -> option.Option(BitArray) {
  message_authenticator_loop(attributes)
}

pub fn with_event_timestamp(
  attributes: List(RadiusAttribute),
  timestamp: Int,
) -> List(RadiusAttribute) {
  [
    RadiusAttribute(type_id: 55, value: <<timestamp:32>>),
    ..remove_attributes(attributes, 55)
  ]
}

pub fn with_message_authenticator_placeholder(
  attributes: List(RadiusAttribute),
) -> List(RadiusAttribute) {
  [
    RadiusAttribute(type_id: 80, value: <<
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    >>),
    ..remove_attributes(attributes, 80)
  ]
}

fn reply_message_loop(
  attributes: List(RadiusAttribute),
) -> option.Option(String) {
  case attributes {
    [] -> option.None
    [RadiusAttribute(type_id: 18, value: value), ..rest] ->
      case bit_array.to_string(value) {
        Ok(message) -> option.Some(message)
        Error(_) -> reply_message_loop(rest)
      }
    [_, ..rest] -> reply_message_loop(rest)
  }
}

fn event_timestamp_loop(attributes: List(RadiusAttribute)) -> option.Option(Int) {
  case attributes {
    [] -> option.None
    [RadiusAttribute(type_id: 55, value: value), ..rest] ->
      case value {
        <<timestamp:32>> -> option.Some(timestamp)
        _ -> event_timestamp_loop(rest)
      }
    [_, ..rest] -> event_timestamp_loop(rest)
  }
}

fn message_authenticator_loop(
  attributes: List(RadiusAttribute),
) -> option.Option(BitArray) {
  case attributes {
    [] -> option.None
    [RadiusAttribute(type_id: 80, value: value), ..rest] ->
      case bit_array.byte_size(value) == 16 {
        True -> option.Some(value)
        False -> message_authenticator_loop(rest)
      }
    [_, ..rest] -> message_authenticator_loop(rest)
  }
}

fn selector_to_attributes(
  selector: snapshot.SessionSelector,
) -> Result(List(RadiusAttribute), PacketError) {
  let snapshot.SessionSelector(
    username: username,
    framed_ip: framed_ip,
    acct_session_id: acct_session_id,
    nas_ip_address: nas_ip_address,
  ) = selector

  use username_attributes <- result.try(option_string_attribute(username, 1))
  use framed_ip_attributes <- result.try(option_ip_attribute(framed_ip, 8))
  use acct_session_id_attributes <- result.try(option_string_attribute(
    acct_session_id,
    44,
  ))
  use nas_ip_attributes <- result.try(option_ip_attribute(nas_ip_address, 4))

  Ok(list.append(
    username_attributes,
    list.append(
      framed_ip_attributes,
      list.append(acct_session_id_attributes, nas_ip_attributes),
    ),
  ))
}

fn option_string_attribute(
  value: option.Option(String),
  type_id: Int,
) -> Result(List(RadiusAttribute), PacketError) {
  case value {
    option.None -> Ok([])
    option.Some(item) ->
      Ok([RadiusAttribute(type_id: type_id, value: bit_array.from_string(item))])
  }
}

fn option_ip_attribute(
  value: option.Option(String),
  type_id: Int,
) -> Result(List(RadiusAttribute), PacketError) {
  case value {
    option.None -> Ok([])
    option.Some(item) -> {
      use encoded <- result.try(ipv4_to_bits(item))
      Ok([RadiusAttribute(type_id: type_id, value: encoded)])
    }
  }
}

// Why: the transport layer must translate named policy attrs into concrete
// RADIUS AVPs so a live UDP CoA request carries actual protocol fields.
fn named_attributes_to_radius(
  remaining: List(vendor_types.RadiusAttribute),
  vendor: vendor_types.RadiusVendor,
  acc: List(RadiusAttribute),
) -> Result(List(RadiusAttribute), PacketError) {
  case remaining {
    [] -> Ok(list.reverse(acc))
    [attribute, ..rest] ->
      case named_attribute_to_radius(attribute, vendor) {
        Ok(mapped) ->
          named_attributes_to_radius(
            rest,
            vendor,
            list.reverse(mapped) |> list.append(acc),
          )
        Error(error) -> Error(error)
      }
  }
}

fn named_attribute_to_radius(
  attribute: vendor_types.RadiusAttribute,
  vendor: vendor_types.RadiusVendor,
) -> Result(List(RadiusAttribute), PacketError) {
  let vendor_types.RadiusAttribute(name: name, value: value) = attribute

  case name {
    "class" | "policy_tag" ->
      Ok([RadiusAttribute(type_id: 25, value: bit_array.from_string(value))])

    "reason" ->
      Ok([RadiusAttribute(type_id: 18, value: bit_array.from_string(value))])

    _ ->
      case string.starts_with(name, "cisco_avpair.") {
        True ->
          Ok([
            RadiusAttribute(
              type_id: 26,
              value: vendor_specific_value(
                9,
                1,
                strip_prefix(name, "cisco_avpair.") <> "=" <> value,
              ),
            ),
          ])

        False ->
          case string.starts_with(name, "dynamic_profile.") {
            True ->
              Ok([
                RadiusAttribute(
                  type_id: 26,
                  value: vendor_specific_value(
                    2636,
                    1,
                    strip_prefix(name, "dynamic_profile.") <> "=" <> value,
                  ),
                ),
              ])

            False ->
              case string.starts_with(name, "api.policy.") {
                True ->
                  Error(UnsupportedLiveVendor(vendor: vendor_to_string(vendor)))

                False -> Error(UnsupportedLiveAttribute(name: name))
              }
          }
      }
  }
}

fn vendor_specific_value(
  vendor_id: Int,
  vendor_type: Int,
  content: String,
) -> BitArray {
  let content_bits = bit_array.from_string(content)
  let vendor_length = 2 + bit_array.byte_size(content_bits)
  <<vendor_id:32, vendor_type, vendor_length, content_bits:bits>>
}

fn vendor_to_string(vendor: vendor_types.RadiusVendor) -> String {
  case vendor {
    vendor_types.Cisco -> "cisco"
    vendor_types.Juniper -> "juniper"
    vendor_types.Vbng -> "vbng"
  }
}

fn strip_prefix(value: String, prefix: String) -> String {
  let prefix_length = string.byte_size(prefix)
  case string.byte_size(value) >= prefix_length {
    True ->
      string.slice(
        value,
        prefix_length,
        string.byte_size(value) - prefix_length,
      )
    False -> value
  }
}

fn ipv4_to_bits(value: String) -> Result(BitArray, PacketError) {
  case string.split(value, ".") {
    [first, second, third, fourth] -> {
      use first_octet <- result.try(parse_octet(first, value))
      use second_octet <- result.try(parse_octet(second, value))
      use third_octet <- result.try(parse_octet(third, value))
      use fourth_octet <- result.try(parse_octet(fourth, value))
      Ok(<<first_octet, second_octet, third_octet, fourth_octet>>)
    }
    _ -> Error(InvalidIpAddress(value: value))
  }
}

fn parse_octet(part: String, original: String) -> Result(Int, PacketError) {
  case int.parse(part) {
    Ok(value) ->
      case value >= 0 && value <= 255 {
        True -> Ok(value)
        False -> Error(InvalidIpAddress(value: original))
      }
    Error(_) -> Error(InvalidIpAddress(value: original))
  }
}

fn encode_attributes(
  attributes: List(RadiusAttribute),
  acc: List(BitArray),
) -> BitArray {
  case attributes {
    [] -> bit_array.concat(list.reverse(acc))
    [attribute, ..rest] ->
      encode_attributes(rest, [encode_attribute(attribute), ..acc])
  }
}

fn encode_attribute(attribute: RadiusAttribute) -> BitArray {
  let RadiusAttribute(type_id: type_id, value: value) = attribute
  let length = 2 + bit_array.byte_size(value)
  <<type_id, length, value:bits>>
}

fn decode_attributes(
  payload: BitArray,
  acc: List(RadiusAttribute),
) -> Result(List(RadiusAttribute), PacketError) {
  case bit_array.byte_size(payload) {
    0 -> Ok(list.reverse(acc))
    size if size < 2 -> Error(InvalidAttributeLength(type_id: 0, length: size))
    _ -> {
      use type_id <- result.try(byte_at(payload, 0))
      use length <- result.try(byte_at(payload, 1))

      case length < 2 || length > bit_array.byte_size(payload) {
        True -> Error(InvalidAttributeLength(type_id: type_id, length: length))
        False -> {
          use value <- result.try(slice(payload, 2, length - 2))
          use rest <- result.try(slice(
            payload,
            length,
            bit_array.byte_size(payload) - length,
          ))
          decode_attributes(rest, [
            RadiusAttribute(type_id: type_id, value: value),
            ..acc
          ])
        }
      }
    }
  }
}

fn radius_code_from_int(code: Int) -> Result(RadiusCode, PacketError) {
  case code {
    40 -> Ok(DisconnectRequestCode)
    41 -> Ok(DisconnectAckCode)
    42 -> Ok(DisconnectNakCode)
    43 -> Ok(CoaRequestCode)
    44 -> Ok(CoaAckCode)
    45 -> Ok(CoaNakCode)
    _ -> Error(InvalidCode(code: code))
  }
}

pub fn radius_code_to_int(code: RadiusCode) -> Int {
  case code {
    DisconnectRequestCode -> 40
    DisconnectAckCode -> 41
    DisconnectNakCode -> 42
    CoaRequestCode -> 43
    CoaAckCode -> 44
    CoaNakCode -> 45
  }
}

fn remove_attributes(
  attributes: List(RadiusAttribute),
  type_id: Int,
) -> List(RadiusAttribute) {
  list.filter(attributes, fn(attribute) {
    let RadiusAttribute(type_id: attribute_type_id, value: _value) = attribute
    attribute_type_id != type_id
  })
}

fn byte_at(payload: BitArray, position: Int) -> Result(Int, PacketError) {
  use slice_value <- result.try(slice(payload, position, 1))
  case slice_value {
    <<value>> -> Ok(value)
    _ -> Error(PacketTooShort)
  }
}

fn uint16_at(payload: BitArray, position: Int) -> Result(Int, PacketError) {
  use slice_value <- result.try(slice(payload, position, 2))
  case slice_value {
    <<value:16>> -> Ok(value)
    _ -> Error(PacketTooShort)
  }
}

fn slice(payload: BitArray, at: Int, take: Int) -> Result(BitArray, PacketError) {
  case bit_array.slice(payload, at, take) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(PacketTooShort)
  }
}
