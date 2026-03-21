import oxion/radius/registry/types

pub type StatusRequest {
  StatusRequest(endpoint_id: String, requires_message_authenticator: Bool)
}

pub type StatusResult {
  Reachable
  Unreachable(reason: String)
}

pub fn build_request(endpoint: types.NasEndpoint) -> StatusRequest {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: capabilities,
  ) = endpoint
  let types.NasCapabilities(
    supports_coa: _supports_coa,
    supports_disconnect: _supports_disconnect,
    supports_status_server: _supports_status_server,
    requires_message_authenticator: requires_message_authenticator,
    requires_event_timestamp: _requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  StatusRequest(
    endpoint_id: endpoint_id,
    requires_message_authenticator: requires_message_authenticator,
  )
}
