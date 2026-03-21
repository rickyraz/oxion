import oxion/radius/disconnect/request
import oxion/radius/registry/capability
import oxion/radius/registry/types

pub type DisconnectPreparationError {
  DisconnectUnsupportedByEndpoint(endpoint_id: String)
  UnsupportedTransport(kind: types.TransportKind)
}

pub type DisconnectPlan {
  DisconnectPlan(
    request: request.DisconnectRequest,
    endpoint: types.NasEndpoint,
  )
}

pub fn prepare(
  request_value: request.DisconnectRequest,
  endpoint: types.NasEndpoint,
) -> Result(DisconnectPlan, DisconnectPreparationError) {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: endpoint_id,
    vendor: _vendor,
    transport: transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: capabilities,
  ) = endpoint

  case capability.supports_dynamic_authorization(capabilities) {
    False -> Error(DisconnectUnsupportedByEndpoint(endpoint_id: endpoint_id))
    True ->
      case transport {
        types.Udp | types.RadSec ->
          Ok(DisconnectPlan(request: request_value, endpoint: endpoint))
      }
  }
}
