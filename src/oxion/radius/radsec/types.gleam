import gleam/option

pub type RadSecConfig {
  RadSecConfig(
    ca_cert_path: String,
    client_cert_path: option.Option(String),
    client_key_path: option.Option(String),
    server_name: option.Option(String),
    connect_timeout_ms: Int,
    idle_timeout_ms: Int,
    max_connections: Int,
  )
}

pub type RadSecError {
  InvalidTlsConfig(reason: String)
}
