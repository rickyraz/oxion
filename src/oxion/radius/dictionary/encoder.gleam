import gleam/bit_array
import gleam/int
import gleam/option
import gleam/result
import gleam/string
import oxion/radius/dictionary/registry
import oxion/radius/dictionary/types
import oxion/radius/packet

pub type EncodeError {
  RegistryError(error: types.RegistryError)
  InvalidIntegerValue(logical_name: String, value: String)
  InvalidIpAddress(logical_name: String, value: String)
  InvalidOctetsLength(logical_name: String)
}

pub fn encode_named(
  family: types.PacketFamily,
  logical_name: String,
  value: String,
) -> Result(packet.RadiusAttribute, EncodeError) {
  case registry.lookup(logical_name) {
    Error(error) -> Error(RegistryError(error: error))
    Ok(spec) ->
      case registry.validate_allowed_in(spec, family) {
        Error(error) -> Error(RegistryError(error: error))
        Ok(validated_spec) -> encode(validated_spec, logical_name, value)
      }
  }
}

// Why: encoder ownership belongs in the dictionary layer so vendor renderers can
// emit logical attrs while the packet layer only consumes concrete wire attrs.
pub fn encode(
  spec: types.RadiusAttributeSpec,
  logical_name: String,
  value: String,
) -> Result(packet.RadiusAttribute, EncodeError) {
  let encoded_value_result = case spec.data_type {
    types.Text -> Ok(bit_array.from_string(value))
    types.Integer -> encode_integer(logical_name, value)
    types.IpV4 -> encode_ipv4(logical_name, value)
    types.IpV6 -> Ok(bit_array.from_string(value))
    types.Octets -> encode_octets(logical_name, value)
    types.Tlv -> Ok(bit_array.from_string(value))
  }
  use encoded_value <- result.try(encoded_value_result)

  case spec.protocol_family {
    types.Standard | types.Evs ->
      Ok(packet.RadiusAttribute(type_id: spec.radius_type, value: encoded_value))
    types.Vsa ->
      case spec.vendor_id, spec.vendor_type {
        option.Some(encoded_vendor_id), option.Some(encoded_vendor_type) ->
          Ok(packet.RadiusAttribute(
            type_id: spec.radius_type,
            value: vendor_specific_value(
              encoded_vendor_id,
              encoded_vendor_type,
              encoded_value,
            ),
          ))
        _, _ ->
          Error(
            RegistryError(error: types.UnknownAttribute(
              logical_name: logical_name,
            )),
          )
      }
  }
}

fn encode_integer(
  logical_name: String,
  value: String,
) -> Result(BitArray, EncodeError) {
  case int.parse(value) {
    Ok(parsed) -> Ok(<<parsed:32>>)
    Error(_) ->
      Error(InvalidIntegerValue(logical_name: logical_name, value: value))
  }
}

fn encode_octets(
  logical_name: String,
  value: String,
) -> Result(BitArray, EncodeError) {
  let encoded = bit_array.from_string(value)

  case bit_array.byte_size(encoded) > 0 {
    True -> Ok(encoded)
    False -> Error(InvalidOctetsLength(logical_name: logical_name))
  }
}

fn encode_ipv4(
  logical_name: String,
  value: String,
) -> Result(BitArray, EncodeError) {
  case string_to_octets(value) {
    Ok(#(first, second, third, fourth)) -> Ok(<<first, second, third, fourth>>)
    Error(_) ->
      Error(InvalidIpAddress(logical_name: logical_name, value: value))
  }
}

fn string_to_octets(value: String) -> Result(#(Int, Int, Int, Int), Nil) {
  case string.split(value, ".") {
    [first, second, third, fourth] -> {
      use first_octet <- result.try(parse_octet(first))
      use second_octet <- result.try(parse_octet(second))
      use third_octet <- result.try(parse_octet(third))
      use fourth_octet <- result.try(parse_octet(fourth))
      Ok(#(first_octet, second_octet, third_octet, fourth_octet))
    }
    _ -> Error(Nil)
  }
}

fn parse_octet(part: String) -> Result(Int, Nil) {
  case int.parse(part) {
    Ok(value) if value >= 0 && value <= 255 -> Ok(value)
    _ -> Error(Nil)
  }
}

fn vendor_specific_value(
  vendor_id: Int,
  vendor_type: Int,
  content: BitArray,
) -> BitArray {
  let vendor_length = 2 + bit_array.byte_size(content)
  <<vendor_id:32, vendor_type, vendor_length, content:bits>>
}
