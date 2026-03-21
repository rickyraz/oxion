import gleam/option
import oxion/radius/packet

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
