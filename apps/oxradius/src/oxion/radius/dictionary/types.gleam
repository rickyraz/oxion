import gleam/option

pub type ProtocolFamily {
  Standard
  Vsa
  Evs
}

pub type RadiusDataType {
  Text
  Integer
  IpV4
  IpV6
  Octets
  Tlv
}

pub type PacketFamily {
  Access
  Accounting
  CoA
  Disconnect
  Status
}

pub type AttributeRole {
  Selector
  AuthorizationChange
  ReplyOnly
  AccountingOnly
}

pub type RadiusAttributeSpec {
  RadiusAttributeSpec(
    logical_name: String,
    protocol_family: ProtocolFamily,
    radius_type: Int,
    vendor_id: option.Option(Int),
    vendor_type: option.Option(Int),
    data_type: RadiusDataType,
    allowed_in: List(PacketFamily),
    role: AttributeRole,
    value_prefix: option.Option(String),
    freeradius_name: String,
    source_ref: String,
  )
}

pub type RegistryError {
  UnknownAttribute(logical_name: String)
  UnsupportedPacketFamily(logical_name: String, family: PacketFamily)
}
