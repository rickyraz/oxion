import gleam/option
import oxion/radius/vendor/types as vendor_types

pub type SecretRef {
  InlineSecret(value: String)
  EnvSecret(name: String)
  VaultSecret(path: String, key: String)
}

pub type TransportKind {
  Udp
  RadSec
}

pub type NasCapabilities {
  NasCapabilities(
    supports_coa: Bool,
    supports_disconnect: Bool,
    supports_status_server: Bool,
    requires_message_authenticator: Bool,
    requires_event_timestamp: Bool,
    supports_multi_session_match: Bool,
  )
}

pub type EndpointSelector {
  EndpointSelector(
    nas_ip_address: option.Option(String),
    nas_identifier: option.Option(String),
  )
}

pub type NasEndpoint {
  NasEndpoint(
    tenant_id: String,
    endpoint_id: String,
    vendor: vendor_types.RadiusVendor,
    transport: TransportKind,
    coa_host: String,
    coa_port: Int,
    secret_ref: SecretRef,
    timeout_ms: Int,
    retry_profile_id: String,
    nas_ip_address: option.Option(String),
    nas_identifier: option.Option(String),
    capabilities: NasCapabilities,
  )
}

pub type RegistryError {
  MissingEndpointSelector
  NoEndpointMatch
  MultipleEndpointMatches
  InvalidEndpoint(reason: String)
}
