import gleam/option

pub type ConnectionMode {
  Persistent
  Trunked
}

pub type TlsVerification {
  VerifyPeer
  SkipPeerVerification
}

pub type RadSecConfig {
  RadSecConfig(
    ca_cert_path: String,
    client_cert_path: option.Option(String),
    client_key_path: option.Option(String),
    server_name: option.Option(String),
    connect_timeout_ms: Int,
    idle_timeout_ms: Int,
    max_connections: Int,
    verification_mode: TlsVerification,
  )
}

pub type ConnectionTarget {
  ConnectionTarget(
    endpoint_id: String,
    host: String,
    port: Int,
    mode: ConnectionMode,
  )
}

pub type PreparedTransport {
  PreparedTransport(
    endpoint_id: String,
    host: String,
    port: Int,
    mode: ConnectionMode,
    server_name: option.Option(String),
    mutual_tls: Bool,
    max_connections: Int,
  )
}

pub type RadSecError {
  InvalidTlsConfig(reason: String)
  UnsupportedEndpointTransport(kind: String)
  InvalidEndpoint(reason: String)
}
