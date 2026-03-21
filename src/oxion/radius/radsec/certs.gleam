import gleam/option
import oxion/radius/radsec/types

pub fn validate(config: types.RadSecConfig) -> Result(Nil, types.RadSecError) {
  let types.RadSecConfig(
    ca_cert_path: ca_cert_path,
    client_cert_path: client_cert_path,
    client_key_path: client_key_path,
    server_name: server_name,
    connect_timeout_ms: connect_timeout_ms,
    idle_timeout_ms: idle_timeout_ms,
    max_connections: max_connections,
    verification_mode: verification_mode,
  ) = config

  case ca_cert_path == "" {
    True -> Error(types.InvalidTlsConfig(reason: "missing_ca_cert_path"))
    False ->
      case incomplete_mutual_tls(client_cert_path, client_key_path) {
        True ->
          Error(types.InvalidTlsConfig(
            reason: "client_cert_and_key_must_be_configured_together",
          ))
        False ->
          case empty_server_name(server_name) {
            True -> Error(types.InvalidTlsConfig(reason: "empty_server_name"))
            False ->
              case
                connect_timeout_ms > 0
                && idle_timeout_ms > 0
                && max_connections > 0
              {
                False ->
                  Error(types.InvalidTlsConfig(
                    reason: "invalid_timeout_or_pool_settings",
                  ))
                True ->
                  case verification_mode {
                    types.SkipPeerVerification ->
                      Error(types.InvalidTlsConfig(
                        reason: "peer_verification_must_not_be_disabled",
                      ))
                    types.VerifyPeer -> Ok(Nil)
                  }
              }
          }
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
    verification_mode: _verification_mode,
  ) = config

  case client_cert_path, client_key_path {
    option.Some(_), option.Some(_) -> True
    _, _ -> False
  }
}

fn incomplete_mutual_tls(
  client_cert_path: option.Option(String),
  client_key_path: option.Option(String),
) -> Bool {
  case client_cert_path, client_key_path {
    option.Some(_), option.None -> True
    option.None, option.Some(_) -> True
    _, _ -> False
  }
}

fn empty_server_name(server_name: option.Option(String)) -> Bool {
  case server_name {
    option.Some(value) -> value == ""
    option.None -> False
  }
}
