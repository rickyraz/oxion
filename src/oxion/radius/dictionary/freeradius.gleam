import gleam/int
import gleam/option
import oxion/radius/dictionary/types

pub fn render_attribute(spec: types.RadiusAttributeSpec) -> String {
  let types.RadiusAttributeSpec(
    logical_name: _logical_name,
    protocol_family: _protocol_family,
    radius_type: radius_type,
    vendor_id: vendor_id,
    vendor_type: _vendor_type,
    data_type: data_type,
    allowed_in: _allowed_in,
    role: _role,
    value_prefix: _value_prefix,
    freeradius_name: freeradius_name,
    source_ref: _source_ref,
  ) = spec

  case vendor_id {
    option.None ->
      "ATTRIBUTE "
      <> freeradius_name
      <> " "
      <> int.to_string(radius_type)
      <> " "
      <> data_type_name(data_type)
    option.Some(_) ->
      "ATTRIBUTE "
      <> freeradius_name
      <> " "
      <> int.to_string(radius_type)
      <> " "
      <> data_type_name(data_type)
  }
}

fn data_type_name(data_type: types.RadiusDataType) -> String {
  case data_type {
    types.Text -> "string"
    types.Integer -> "integer"
    types.IpV4 -> "ipaddr"
    types.IpV6 -> "ipv6addr"
    types.Octets -> "octets"
    types.Tlv -> "tlv"
  }
}
