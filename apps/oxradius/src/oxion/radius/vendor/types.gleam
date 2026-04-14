pub type RadiusVendor {
  Cisco
  Juniper
  Vbng
}

pub type RadiusAttribute {
  RadiusAttribute(name: String, value: String)
}

pub type VendorAdapterError {
  MissingRequiredField(field: String)
  InvalidBandwidth(field: String)
  UnsupportedAccessAction(action: String)
}
