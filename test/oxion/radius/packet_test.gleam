import gleam/option
import oxion/radius/coa/request
import oxion/radius/packet
import oxion/radius/profile/snapshot
import oxion/radius/vendor/types as vendor_types

pub fn packet_extracts_security_attributes_test() {
  let attributes =
    packet.with_message_authenticator_placeholder(packet.with_event_timestamp(
      [],
      1_710_000_000,
    ))

  assert packet.event_timestamp(attributes) == option.Some(1_710_000_000)
  assert packet.message_authenticator(attributes)
    == option.Some(<<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>)
}

pub fn packet_decodes_disconnect_request_code_test() {
  assert packet.decode_packet(<<
      40,
      7,
      0,
      20,
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
    >>)
    == Ok(
      packet.RadiusPacket(
        code: packet.DisconnectRequestCode,
        identifier: 7,
        length: 20,
        authenticator: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
        attributes: [],
      ),
    )
}

pub fn packet_decodes_status_and_access_codes_test() {
  assert packet.decode_packet(<<
      12,
      7,
      0,
      20,
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
    >>)
    == Ok(
      packet.RadiusPacket(
        code: packet.StatusServerCode,
        identifier: 7,
        length: 20,
        authenticator: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
        attributes: [],
      ),
    )

  assert packet.decode_packet(<<
      2,
      8,
      0,
      20,
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
    >>)
    == Ok(
      packet.RadiusPacket(
        code: packet.AccessAcceptCode,
        identifier: 8,
        length: 20,
        authenticator: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
        attributes: [],
      ),
    )
}

pub fn packet_encodes_hardened_coa_request_test() {
  let request_value =
    request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_soft_throttle",
      action_fingerprint: "fp:packet:secure",
      session_selector: snapshot.SessionSelector(
        username: option.Some("cust_001"),
        framed_ip: option.Some("10.10.20.5"),
        acct_session_id: option.None,
        nas_ip_address: option.None,
      ),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "class",
          value: "throttled_due_overdue",
        ),
      ],
      disconnect_hint: False,
    )

  case
    packet.encode_coa_request_with_security(
      request_value,
      vendor_types.Cisco,
      "sharedsecret",
      packet.PacketSecurityConfig(
        message_authenticator: True,
        event_timestamp: option.Some(1_710_000_000),
      ),
    )
  {
    Ok(encoded_request) ->
      case packet.decode_packet(encoded_request.payload) {
        Ok(decoded_packet) -> {
          assert packet.event_timestamp(decoded_packet.attributes)
            == option.Some(1_710_000_000)
          case packet.message_authenticator(decoded_packet.attributes) {
            option.Some(message_authenticator) -> {
              assert message_authenticator
                != <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
            }
            option.None -> panic
          }
        }
        Error(_) -> panic
      }
    Error(_) -> panic
  }
}

pub fn packet_keeps_legacy_cisco_attribute_names_compatible_test() {
  let request_value =
    request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_soft_throttle",
      action_fingerprint: "fp:packet:legacy-cisco",
      session_selector: snapshot.SessionSelector(
        username: option.Some("cust_001"),
        framed_ip: option.None,
        acct_session_id: option.None,
        nas_ip_address: option.None,
      ),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "cisco_avpair.service_profile",
          value: "bw_4mbps",
        ),
      ],
      disconnect_hint: False,
    )

  case
    packet.encode_coa_request_with_security(
      request_value,
      vendor_types.Cisco,
      "sharedsecret",
      packet.default_security_config(),
    )
  {
    Ok(_encoded_request) -> Nil
    Error(_) -> panic
  }
}

pub fn packet_rejects_vbng_live_attributes_test() {
  let request_value =
    request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_soft_throttle",
      action_fingerprint: "fp:packet:vbng",
      session_selector: snapshot.SessionSelector(
        username: option.Some("cust_001"),
        framed_ip: option.None,
        acct_session_id: option.None,
        nas_ip_address: option.None,
      ),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "vbng.profile_id",
          value: "gold-profile",
        ),
      ],
      disconnect_hint: False,
    )

  assert packet.encode_coa_request_with_security(
      request_value,
      vendor_types.Vbng,
      "sharedsecret",
      packet.default_security_config(),
    )
    == Error(packet.UnsupportedLiveVendor(vendor: "vbng"))
}
