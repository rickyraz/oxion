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
      option.None,
      "User-Name",
      "RFC2865",
    ),
    standard(
      "nas_ip_address",
      4,
      types.IpV4,
      [types.CoA, types.Disconnect],
      types.Selector,
      option.None,
      "NAS-IP-Address",
      "RFC2865",
    ),
    standard(
      "framed_ip_address",
      8,
      types.IpV4,
      [types.CoA, types.Disconnect],
      types.Selector,
      option.None,
      "Framed-IP-Address",
      "RFC2865",
    ),
    standard(
      "reply_message",
      18,
      types.Text,
      [types.CoA, types.Disconnect],
      types.ReplyOnly,
      option.None,
      "Reply-Message",
      "RFC2865",
    ),
    standard(
      "class",
      25,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.None,
      "Class",
      "RFC2865",
    ),
    standard(
      "acct_session_id",
      44,
      types.Text,
      [types.CoA, types.Disconnect],
      types.Selector,
      option.None,
      "Acct-Session-Id",
      "RFC2866",
    ),
    standard(
      "event_timestamp",
      55,
      types.Integer,
      [types.CoA, types.Disconnect, types.Status],
      types.AuthorizationChange,
      option.None,
      "Event-Timestamp",
      "RFC2869",
    ),
    standard(
      "message_authenticator",
      80,
      types.Octets,
      [types.CoA, types.Disconnect, types.Status],
      types.AuthorizationChange,
      option.None,
      "Message-Authenticator",
      "RFC2869",
    ),
    standard(
      "error_cause",
      101,
      types.Integer,
      [types.CoA, types.Disconnect],
      types.ReplyOnly,
      option.None,
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
      option.None,
      "Cisco-AVPair",
      "Cisco VSA",
    ),
    vsa(
      "cisco.service_profile",
      9,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("service_profile="),
      "Cisco-AVPair",
      "Cisco VSA service profile",
    ),
    vsa(
      "cisco.qos_down",
      9,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("qos_down="),
      "Cisco-AVPair",
      "Cisco VSA downstream policer",
    ),
    vsa(
      "cisco.qos_up",
      9,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("qos_up="),
      "Cisco-AVPair",
      "Cisco VSA upstream policer",
    ),
    vsa(
      "cisco.access_action",
      9,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("access_action="),
      "Cisco-AVPair",
      "Cisco VSA access action",
    ),
    vsa(
      "juniper.avpair",
      2636,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.None,
      "ERX-Dynamic-Profile-Name",
      "Juniper Dynamic Profile",
    ),
    vsa(
      "juniper.profile_name",
      2636,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("name="),
      "ERX-Dynamic-Profile-Name",
      "Juniper dynamic profile name",
    ),
    vsa(
      "juniper.policer_down",
      2636,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("policer_down="),
      "ERX-Dynamic-Profile-Name",
      "Juniper downstream policer",
    ),
    vsa(
      "juniper.policer_up",
      2636,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("policer_up="),
      "ERX-Dynamic-Profile-Name",
      "Juniper upstream policer",
    ),
    vsa(
      "juniper.access_action",
      2636,
      1,
      types.Text,
      [types.CoA],
      types.AuthorizationChange,
      option.Some("access_action="),
      "ERX-Dynamic-Profile-Name",
      "Juniper access action",
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
    value_prefix: _value_prefix,
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
    value_prefix: _value_prefix,
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
  value_prefix: option.Option(String),
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
    value_prefix: value_prefix,
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
  value_prefix: option.Option(String),
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
    value_prefix: value_prefix,
    freeradius_name: freeradius_name,
    source_ref: source_ref,
  )
}
