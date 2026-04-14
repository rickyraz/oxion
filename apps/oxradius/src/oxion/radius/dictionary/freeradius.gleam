import gleam/int
import gleam/list
import gleam/option
import gleam/string
import oxion/radius/dictionary/registry
import oxion/radius/dictionary/types

pub fn render_default_dictionary() -> String {
  render_dictionary(registry.all())
}

pub fn render_dictionary(specs: List(types.RadiusAttributeSpec)) -> String {
  let standard_lines =
    dedupe_physical_specs(specs)
    |> list.filter(fn(spec) { is_standard_or_evs(spec) })
    |> list.map(render_physical_attribute)
  let vendor_groups = vendor_group_names(specs)
  let vendor_lines =
    list.flat_map(vendor_groups, fn(group) { render_vendor_group(group, specs) })
  let all_lines = list.append(standard_lines, vendor_lines)

  string.join(all_lines, "\n")
}

// Why: internal logical names intentionally fan into fewer physical AVPs/VSAs,
// so dictionary rendering must deduplicate by wire attribute instead of
// emitting one FreeRADIUS definition per logical mapping.
pub fn render_attribute(spec: types.RadiusAttributeSpec) -> String {
  render_physical_attribute(spec)
}

fn render_vendor_group(
  group: #(Int, String),
  specs: List(types.RadiusAttributeSpec),
) -> List(String) {
  let #(vendor_id, vendor_name) = group
  let vendor_specs =
    dedupe_physical_specs(specs)
    |> list.filter(fn(spec) { belongs_to_vendor(spec, vendor_id) })
    |> list.map(render_physical_attribute)

  case vendor_specs {
    [] -> []
    _ -> [
      "VENDOR " <> vendor_name <> " " <> int.to_string(vendor_id),
      "BEGIN-VENDOR " <> vendor_name,
      ..list.append(vendor_specs, ["END-VENDOR " <> vendor_name])
    ]
  }
}

fn render_physical_attribute(spec: types.RadiusAttributeSpec) -> String {
  let types.RadiusAttributeSpec(
    logical_name: _logical_name,
    protocol_family: _protocol_family,
    radius_type: radius_type,
    vendor_id: vendor_id,
    vendor_type: vendor_type,
    data_type: data_type,
    allowed_in: _allowed_in,
    role: _role,
    value_prefix: _value_prefix,
    freeradius_name: freeradius_name,
    source_ref: _source_ref,
  ) = spec

  case vendor_id, vendor_type {
    option.Some(_), option.Some(physical_vendor_type) ->
      "ATTRIBUTE "
      <> freeradius_name
      <> " "
      <> int.to_string(physical_vendor_type)
      <> " "
      <> data_type_name(data_type)
    _, _ ->
      "ATTRIBUTE "
      <> freeradius_name
      <> " "
      <> int.to_string(radius_type)
      <> " "
      <> data_type_name(data_type)
  }
}

fn dedupe_physical_specs(
  specs: List(types.RadiusAttributeSpec),
) -> List(types.RadiusAttributeSpec) {
  dedupe_physical_specs_loop(specs, [])
}

fn dedupe_physical_specs_loop(
  remaining: List(types.RadiusAttributeSpec),
  acc: List(types.RadiusAttributeSpec),
) -> List(types.RadiusAttributeSpec) {
  case remaining {
    [] -> list.reverse(acc)
    [spec, ..rest] ->
      case
        list.any(acc, fn(candidate) { same_physical_attribute(spec, candidate) })
      {
        True -> dedupe_physical_specs_loop(rest, acc)
        False -> dedupe_physical_specs_loop(rest, [spec, ..acc])
      }
  }
}

fn same_physical_attribute(
  left: types.RadiusAttributeSpec,
  right: types.RadiusAttributeSpec,
) -> Bool {
  let types.RadiusAttributeSpec(
    logical_name: _left_logical_name,
    protocol_family: left_protocol_family,
    radius_type: left_radius_type,
    vendor_id: left_vendor_id,
    vendor_type: left_vendor_type,
    data_type: left_data_type,
    allowed_in: _left_allowed_in,
    role: _left_role,
    value_prefix: _left_value_prefix,
    freeradius_name: left_freeradius_name,
    source_ref: _left_source_ref,
  ) = left
  let types.RadiusAttributeSpec(
    logical_name: _right_logical_name,
    protocol_family: right_protocol_family,
    radius_type: right_radius_type,
    vendor_id: right_vendor_id,
    vendor_type: right_vendor_type,
    data_type: right_data_type,
    allowed_in: _right_allowed_in,
    role: _right_role,
    value_prefix: _right_value_prefix,
    freeradius_name: right_freeradius_name,
    source_ref: _right_source_ref,
  ) = right

  left_protocol_family == right_protocol_family
  && left_radius_type == right_radius_type
  && left_vendor_id == right_vendor_id
  && left_vendor_type == right_vendor_type
  && left_data_type == right_data_type
  && left_freeradius_name == right_freeradius_name
}

fn vendor_group_names(
  specs: List(types.RadiusAttributeSpec),
) -> List(#(Int, String)) {
  vendor_group_names_loop(specs, [])
}

fn vendor_group_names_loop(
  remaining: List(types.RadiusAttributeSpec),
  acc: List(#(Int, String)),
) -> List(#(Int, String)) {
  case remaining {
    [] -> list.reverse(acc)
    [spec, ..rest] ->
      case vendor_identity(spec) {
        option.None -> vendor_group_names_loop(rest, acc)
        option.Some(group) ->
          case list.any(acc, fn(candidate) { candidate == group }) {
            True -> vendor_group_names_loop(rest, acc)
            False -> vendor_group_names_loop(rest, [group, ..acc])
          }
      }
  }
}

fn vendor_identity(
  spec: types.RadiusAttributeSpec,
) -> option.Option(#(Int, String)) {
  let types.RadiusAttributeSpec(
    logical_name: _logical_name,
    protocol_family: _protocol_family,
    radius_type: _radius_type,
    vendor_id: vendor_id,
    vendor_type: _vendor_type,
    data_type: _data_type,
    allowed_in: _allowed_in,
    role: _role,
    value_prefix: _value_prefix,
    freeradius_name: _freeradius_name,
    source_ref: _source_ref,
  ) = spec

  case vendor_id {
    option.Some(value) -> option.Some(#(value, vendor_name(value)))
    option.None -> option.None
  }
}

fn belongs_to_vendor(spec: types.RadiusAttributeSpec, vendor_id: Int) -> Bool {
  let types.RadiusAttributeSpec(
    logical_name: _logical_name,
    protocol_family: _protocol_family,
    radius_type: _radius_type,
    vendor_id: candidate_vendor_id,
    vendor_type: _vendor_type,
    data_type: _data_type,
    allowed_in: _allowed_in,
    role: _role,
    value_prefix: _value_prefix,
    freeradius_name: _freeradius_name,
    source_ref: _source_ref,
  ) = spec

  candidate_vendor_id == option.Some(vendor_id)
}

fn is_standard_or_evs(spec: types.RadiusAttributeSpec) -> Bool {
  let types.RadiusAttributeSpec(
    logical_name: _logical_name,
    protocol_family: protocol_family,
    radius_type: _radius_type,
    vendor_id: _vendor_id,
    vendor_type: _vendor_type,
    data_type: _data_type,
    allowed_in: _allowed_in,
    role: _role,
    value_prefix: _value_prefix,
    freeradius_name: _freeradius_name,
    source_ref: _source_ref,
  ) = spec

  case protocol_family {
    types.Standard | types.Evs -> True
    types.Vsa -> False
  }
}

fn vendor_name(vendor_id: Int) -> String {
  case vendor_id {
    9 -> "Cisco"
    2636 -> "Juniper"
    _ -> "Vendor-" <> int.to_string(vendor_id)
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
