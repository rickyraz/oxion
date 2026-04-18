import gleam/option
import oxion/radius/radsec/certs
import oxion/radius/radsec/transport
import oxion/radius/radsec/types
import oxion/radius/registry/capability
import oxion/radius/registry/types as registry_types
import oxion/radius/vendor/types as vendor_types

pub fn radsec_prepare_from_endpoint_accepts_radsec_target_test() {
  let config =
    types.RadSecConfig(
      ca_cert_path: "/etc/ssl/radius-ca.pem",
      client_cert_path: option.Some("/etc/ssl/radius-client.pem"),
      client_key_path: option.Some("/etc/ssl/radius-client.key"),
      server_name: option.Some("radius.example.net"),
      connect_timeout_ms: 1000,
      idle_timeout_ms: 5000,
      max_connections: 4,
      verification_mode: types.VerifyPeer,
    )

  assert transport.from_endpoint(radsec_endpoint(), config)
    == Ok(types.PreparedTransport(
      endpoint_id: "edge_radsec",
      host: "192.0.2.10",
      port: 2083,
      mode: types.Trunked,
      server_name: option.Some("radius.example.net"),
      mutual_tls: True,
      max_connections: 4,
    ))
}

pub fn radsec_prepare_rejects_udp_endpoint_test() {
  let config =
    types.RadSecConfig(
      ca_cert_path: "/etc/ssl/radius-ca.pem",
      client_cert_path: option.None,
      client_key_path: option.None,
      server_name: option.Some("radius.example.net"),
      connect_timeout_ms: 1000,
      idle_timeout_ms: 5000,
      max_connections: 1,
      verification_mode: types.VerifyPeer,
    )

  assert transport.from_endpoint(udp_endpoint(), config)
    == Error(types.UnsupportedEndpointTransport(kind: "udp"))
}

pub fn radsec_certs_reject_incomplete_mutual_tls_test() {
  let config =
    types.RadSecConfig(
      ca_cert_path: "/etc/ssl/radius-ca.pem",
      client_cert_path: option.Some("/etc/ssl/radius-client.pem"),
      client_key_path: option.None,
      server_name: option.Some("radius.example.net"),
      connect_timeout_ms: 1000,
      idle_timeout_ms: 5000,
      max_connections: 1,
      verification_mode: types.VerifyPeer,
    )

  assert certs.validate(config)
    == Error(types.InvalidTlsConfig(
      reason: "client_cert_and_key_must_be_configured_together",
    ))
}

pub fn radsec_certs_reject_disabled_peer_verification_test() {
  let config =
    types.RadSecConfig(
      ca_cert_path: "/etc/ssl/radius-ca.pem",
      client_cert_path: option.None,
      client_key_path: option.None,
      server_name: option.Some("radius.example.net"),
      connect_timeout_ms: 1000,
      idle_timeout_ms: 5000,
      max_connections: 1,
      verification_mode: types.SkipPeerVerification,
    )

  assert certs.validate(config)
    == Error(types.InvalidTlsConfig(
      reason: "peer_verification_must_not_be_disabled",
    ))
}

pub fn radsec_default_mode_uses_persistent_for_single_connection_test() {
  let config =
    types.RadSecConfig(
      ca_cert_path: "/etc/ssl/radius-ca.pem",
      client_cert_path: option.None,
      client_key_path: option.None,
      server_name: option.None,
      connect_timeout_ms: 1000,
      idle_timeout_ms: 5000,
      max_connections: 1,
      verification_mode: types.VerifyPeer,
    )

  assert transport.default_mode(config) == types.Persistent
}

pub fn radsec_prepare_rejects_missing_host_or_port_test() {
  let config =
    types.RadSecConfig(
      ca_cert_path: "/etc/ssl/radius-ca.pem",
      client_cert_path: option.None,
      client_key_path: option.None,
      server_name: option.Some("radius.example.net"),
      connect_timeout_ms: 1000,
      idle_timeout_ms: 5000,
      max_connections: 2,
      verification_mode: types.VerifyPeer,
    )

  assert transport.prepare(
      config,
      types.ConnectionTarget(
        endpoint_id: "edge_radsec",
        host: "",
        port: 2083,
        mode: types.Trunked,
      ),
    )
    == Error(types.InvalidEndpoint(reason: "missing_host_or_port"))
}

fn radsec_endpoint() -> registry_types.NasEndpoint {
  registry_types.NasEndpoint(
    tenant_id: "tenant_a",
    endpoint_id: "edge_radsec",
    vendor: vendor_types.Cisco,
    transport: registry_types.RadSec,
    coa_host: "192.0.2.10",
    coa_port: 2083,
    secret_ref: registry_types.InlineSecret(value: "unused-for-radsec"),
    timeout_ms: 1000,
    retry_profile_id: "radsec",
    nas_ip_address: option.None,
    nas_identifier: option.Some("edge-radsec"),
    capabilities: capability.default_udp_capabilities(),
  )
}

fn udp_endpoint() -> registry_types.NasEndpoint {
  registry_types.NasEndpoint(
    tenant_id: "tenant_a",
    endpoint_id: "edge_udp",
    vendor: vendor_types.Cisco,
    transport: registry_types.Udp,
    coa_host: "192.0.2.20",
    coa_port: 3799,
    secret_ref: registry_types.InlineSecret(value: "sharedsecret"),
    timeout_ms: 1000,
    retry_profile_id: "udp",
    nas_ip_address: option.None,
    nas_identifier: option.Some("edge-udp"),
    capabilities: capability.default_udp_capabilities(),
  )
}
