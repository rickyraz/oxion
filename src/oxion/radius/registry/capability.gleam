import oxion/radius/registry/types

pub fn default_udp_capabilities() -> types.NasCapabilities {
  types.NasCapabilities(
    supports_coa: True,
    supports_disconnect: True,
    supports_status_server: True,
    requires_message_authenticator: True,
    requires_event_timestamp: True,
    supports_multi_session_match: False,
  )
}

pub fn requires_hardened_packets(capabilities: types.NasCapabilities) -> Bool {
  let types.NasCapabilities(
    supports_coa: _supports_coa,
    supports_disconnect: _supports_disconnect,
    supports_status_server: _supports_status_server,
    requires_message_authenticator: requires_message_authenticator,
    requires_event_timestamp: requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  requires_message_authenticator || requires_event_timestamp
}

pub fn supports_dynamic_authorization(
  capabilities: types.NasCapabilities,
) -> Bool {
  let types.NasCapabilities(
    supports_coa: supports_coa,
    supports_disconnect: supports_disconnect,
    supports_status_server: _supports_status_server,
    requires_message_authenticator: _requires_message_authenticator,
    requires_event_timestamp: _requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  supports_coa || supports_disconnect
}
