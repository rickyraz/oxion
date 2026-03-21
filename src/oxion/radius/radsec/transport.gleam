import oxion/radius/radsec/certs
import oxion/radius/radsec/types
import oxion/radius/registry/types as registry_types

pub fn prepare(
  config: types.RadSecConfig,
  target: types.ConnectionTarget,
) -> Result(types.PreparedTransport, types.RadSecError) {
  case certs.validate(config) {
    Ok(_) -> {
      let types.RadSecConfig(
        ca_cert_path: _ca_cert_path,
        client_cert_path: _client_cert_path,
        client_key_path: _client_key_path,
        server_name: server_name,
        connect_timeout_ms: _connect_timeout_ms,
        idle_timeout_ms: _idle_timeout_ms,
        max_connections: max_connections,
        verification_mode: _verification_mode,
      ) = config
      let types.ConnectionTarget(
        endpoint_id: endpoint_id,
        host: host,
        port: port,
        mode: mode,
      ) = target

      case host == "" || port <= 0 {
        True -> Error(types.InvalidEndpoint(reason: "missing_host_or_port"))
        False ->
          Ok(types.PreparedTransport(
            endpoint_id: endpoint_id,
            host: host,
            port: port,
            mode: mode,
            server_name: server_name,
            mutual_tls: certs.has_mutual_tls(config),
            max_connections: max_connections,
          ))
      }
    }
    Error(error) -> Error(error)
  }
}

pub fn from_endpoint(
  endpoint: registry_types.NasEndpoint,
  config: types.RadSecConfig,
) -> Result(types.PreparedTransport, types.RadSecError) {
  let registry_types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: endpoint_id,
    vendor: _vendor,
    transport: transport_kind,
    coa_host: coa_host,
    coa_port: coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: _capabilities,
  ) = endpoint

  case transport_kind {
    registry_types.RadSec ->
      prepare(
        config,
        types.ConnectionTarget(
          endpoint_id: endpoint_id,
          host: coa_host,
          port: coa_port,
          mode: default_mode(config),
        ),
      )
    registry_types.Udp -> Error(types.UnsupportedEndpointTransport(kind: "udp"))
  }
}

pub fn default_mode(config: types.RadSecConfig) -> types.ConnectionMode {
  let types.RadSecConfig(
    ca_cert_path: _ca_cert_path,
    client_cert_path: _client_cert_path,
    client_key_path: _client_key_path,
    server_name: _server_name,
    connect_timeout_ms: _connect_timeout_ms,
    idle_timeout_ms: _idle_timeout_ms,
    max_connections: max_connections,
    verification_mode: _verification_mode,
  ) = config

  case max_connections > 1 {
    True -> types.Trunked
    False -> types.Persistent
  }
}
