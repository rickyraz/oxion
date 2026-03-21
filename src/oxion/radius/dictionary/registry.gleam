import gleam/list
import gleam/option
import oxion/radius/dictionary/types

pub fn all() -> List(types.RadiusAttributeSpec) {
  [
    standard(
      "user_name",
      1,
      types.Text,
      [types.CoA, types.Disconnect],
      types.Selector,
      "User-Name",
      "RFC2865",
    ),
    standard(
      "nas_ip_address",
      4,
      types.IpV4,
      [types.CoA, types.Disconnect],
      types.Selector,
      "NAS-IP-Address",
      "RFC2865",
    ),
    standard(
      "framed_ip_address",
      8,
      types.IpV4,
      [types.CoA, types.Disconnect],
      types.Selector,
      "Framed-IP-Address",
      "RFC2865",
    ),
    standard(
      "reply_message",
      18,
      types.Text,
      [types.CoA, types.Disconnect],
      types.ReplyOnly,
      "Reply-Message",
      "RFC2865",
    ),
    standard(
      "class",
      25,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      "Class",
      "RFC2865",
    ),
    standard(
      "acct_session_id",
      44,
      types.Text,
      [types.CoA, types.Disconnect],
      types.Selector,
      "Acct-Session-Id",
      "RFC2866",
    ),
    standard(
      "event_timestamp",
      55,
      types.Integer,
      [types.CoA, types.Disconnect, types.Status],
      types.AuthorizationChange,
      "Event-Timestamp",
      "RFC2869",
    ),
    standard(
      "message_authenticator",
      80,
      types.Octets,
      [types.CoA, types.Disconnect, types.Status],
      types.AuthorizationChange,
      "Message-Authenticator",
      "RFC2869",
    ),
    standard(
      "error_cause",
      101,
      types.Integer,
      [types.CoA, types.Disconnect],
      types.ReplyOnly,
      "Error-Cause",
      "RFC5176",
    ),
    vsa(
      "cisco.avpair",
      9,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      "Cisco-AVPair",
      "Cisco VSA",
    ),
    vsa(
      "juniper.avpair",
      2636,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      "ERX-Dynamic-Profile-Name",
      "Juniper Dynamic Profile",
    ),
  ]
}

pub fn lookup(
  logical_name: String,
) -> Result(types.RadiusAttributeSpec, types.RegistryError) {
  case list.find(all(), fn(spec) { matches_name(spec, logical_name) }) {
    Ok(spec) -> Ok(spec)
    Error(_) -> Error(types.UnknownAttribute(logical_name: logical_name))
  }
}

pub fn validate_allowed_in(
  spec: types.RadiusAttributeSpec,
  family: types.PacketFamily,
) -> Result(types.RadiusAttributeSpec, types.RegistryError) {
  let types.RadiusAttributeSpec(
    logical_name: logical_name,
    protocol_family: _protocol_family,
    radius_type: _radius_type,
    vendor_id: _vendor_id,
    vendor_type: _vendor_type,
    data_type: _data_type,
    allowed_in: allowed_in,
    role: _role,
    freeradius_name: _freeradius_name,
    source_ref: _source_ref,
  ) = spec

  case list.any(allowed_in, fn(item) { item == family }) {
    True -> Ok(spec)
    False ->
      Error(types.UnsupportedPacketFamily(
        logical_name: logical_name,
        family: family,
      ))
  }
}

fn matches_name(spec: types.RadiusAttributeSpec, logical_name: String) -> Bool {
  let types.RadiusAttributeSpec(
    logical_name: candidate_name,
    protocol_family: _protocol_family,
    radius_type: _radius_type,
    vendor_id: _vendor_id,
    vendor_type: _vendor_type,
    data_type: _data_type,
    allowed_in: _allowed_in,
    role: _role,
    freeradius_name: _freeradius_name,
    source_ref: _source_ref,
  ) = spec

  candidate_name == logical_name
}

fn standard(
  logical_name: String,
  radius_type: Int,
  data_type: types.RadiusDataType,
  allowed_in: List(types.PacketFamily),
  role: types.AttributeRole,
  freeradius_name: String,
  source_ref: String,
) -> types.RadiusAttributeSpec {
  types.RadiusAttributeSpec(
    logical_name: logical_name,
    protocol_family: types.Standard,
    radius_type: radius_type,
    vendor_id: option.None,
    vendor_type: option.None,
    data_type: data_type,
    allowed_in: allowed_in,
    role: role,
    freeradius_name: freeradius_name,
    source_ref: source_ref,
  )
}

fn vsa(
  logical_name: String,
  vendor_id: Int,
  vendor_type: Int,
  data_type: types.RadiusDataType,
  allowed_in: List(types.PacketFamily),
  role: types.AttributeRole,
  freeradius_name: String,
  source_ref: String,
) -> types.RadiusAttributeSpec {
  types.RadiusAttributeSpec(
    logical_name: logical_name,
    protocol_family: types.Vsa,
    radius_type: 26,
    vendor_id: option.Some(vendor_id),
    vendor_type: option.Some(vendor_type),
    data_type: data_type,
    allowed_in: allowed_in,
    role: role,
    freeradius_name: freeradius_name,
    source_ref: source_ref,
  )
}
