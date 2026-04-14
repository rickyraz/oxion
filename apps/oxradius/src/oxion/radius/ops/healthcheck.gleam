import oxion/radius/ops/status
import oxion/radius/registry/capability
import oxion/radius/registry/types

pub type HealthSeverity {
  Healthy
  Degraded
  Critical
}

pub type HealthReport {
  HealthReport(severity: HealthSeverity, reason: String)
}

pub fn evaluate(
  endpoint: types.NasEndpoint,
  status_result: status.StatusResult,
) -> HealthReport {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: _endpoint_id,
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
    supports_status_server: supports_status_server,
    requires_message_authenticator: _requires_message_authenticator,
    requires_event_timestamp: _requires_event_timestamp,
    supports_multi_session_match: _supports_multi_session_match,
  ) = capabilities

  case supports_status_server, status_result {
    False, _ ->
      HealthReport(
        severity: Degraded,
        reason: "status_server_unsupported_by_endpoint",
      )
    True, status.Reachable(response_kind) ->
      case capability.requires_hardened_packets(capabilities) {
        True ->
          HealthReport(
            severity: Healthy,
            reason: "reachable_hardened:" <> response_kind,
          )
        False ->
          HealthReport(
            severity: Degraded,
            reason: "reachable_without_hardening:" <> response_kind,
          )
      }
    True, status.Unreachable(reason) ->
      HealthReport(severity: Critical, reason: "unreachable:" <> reason)
  }
}
