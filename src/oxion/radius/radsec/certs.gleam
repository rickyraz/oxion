import gleam/option
import oxion/radius/radsec/types

pub fn validate(config: types.RadSecConfig) -> Result(Nil, types.RadSecError) {
  let types.RadSecConfig(
    ca_cert_path: ca_cert_path,
    client_cert_path: _client_cert_path,
    client_key_path: _client_key_path,
    server_name: _server_name,
    connect_timeout_ms: connect_timeout_ms,
    idle_timeout_ms: idle_timeout_ms,
    max_connections: max_connections,
  ) = config

  case ca_cert_path == "" {
    True -> Error(types.InvalidTlsConfig(reason: "missing_ca_cert_path"))
    False ->
      case
        connect_timeout_ms > 0 && idle_timeout_ms > 0 && max_connections > 0
      {
        True -> Ok(Nil)
        False ->
          Error(types.InvalidTlsConfig(
            reason: "invalid_timeout_or_pool_settings",
          ))
      }
  }
}

pub fn has_mutual_tls(config: types.RadSecConfig) -> Bool {
  let types.RadSecConfig(
    ca_cert_path: _ca_cert_path,
    client_cert_path: client_cert_path,
    client_key_path: client_key_path,
    server_name: _server_name,
    connect_timeout_ms: _connect_timeout_ms,
    idle_timeout_ms: _idle_timeout_ms,
    max_connections: _max_connections,
  ) = config

  case client_cert_path, client_key_path {
    option.Some(_), option.Some(_) -> True
    _, _ -> False
  }
}
