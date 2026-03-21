import gleam/option
import oxion/radius/dictionary/encoder
import oxion/radius/dictionary/registry
import oxion/radius/dictionary/types

pub fn dictionary_registry_knows_message_authenticator_test() {
  assert registry.lookup("message_authenticator")
    == Ok(types.RadiusAttributeSpec(
      logical_name: "message_authenticator",
      protocol_family: types.Standard,
      radius_type: 80,
      vendor_id: option.None,
      vendor_type: option.None,
      data_type: types.Octets,
      allowed_in: [types.CoA, types.Disconnect, types.Status],
      role: types.AuthorizationChange,
      value_prefix: option.None,
      freeradius_name: "Message-Authenticator",
      source_ref: "RFC2869",
    ))
}

pub fn dictionary_encoder_encodes_error_cause_integer_test() {
  assert encoder.encode_named(types.CoA, "error_cause", "401")
    == Ok(encoder.WireAttribute(type_id: 101, value: <<401:32>>))
}

pub fn dictionary_encoder_encodes_explicit_cisco_vsa_test() {
  assert encoder.encode_named(types.CoA, "cisco.qos_down", "4096")
    == Ok(
      encoder.WireAttribute(type_id: 26, value: <<
        0,
        0,
        0,
        9,
        1,
        15,
        "qos_down=4096":utf8,
      >>),
    )
}
