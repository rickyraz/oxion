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

  case status_result {
    status.Reachable ->
      case capability.requires_hardened_packets(capabilities) {
        True -> HealthReport(severity: Healthy, reason: "reachable_hardened")
        False ->
          HealthReport(
            severity: Degraded,
            reason: "reachable_without_hardening",
          )
      }
    status.Unreachable(reason) ->
      HealthReport(severity: Critical, reason: "unreachable:" <> reason)
  }
}
