import gleam/option
import oxion/radius/ops/healthcheck
import oxion/radius/ops/radclient
import oxion/radius/ops/status
import oxion/radius/registry/capability
import oxion/radius/registry/types as registry_types
import oxion/radius/vendor/types as vendor_types

@external(erlang, "oxion_radius_mock_transport_ffi", "start_status_server")
fn start_status_server(secret: String) -> Result(Int, String)

pub fn status_build_request_rejects_unsupported_endpoint_test() {
  assert status.build_request(
      endpoint_without_status(),
      status.AuthenticationPort,
    )
    == Error(status.StatusUnsupported(endpoint_id: "edge_no_status"))
}

pub fn status_roundtrip_reports_reachable_server_test() {
  let secret = "sharedsecret"
  let port = case start_status_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }
  let endpoint = sample_endpoint(port)
  let request_value = case
    status.build_request(endpoint, status.AuthenticationPort)
  {
    Ok(request_value) -> request_value
    Error(_) -> panic
  }

  assert status.roundtrip(
      request_value,
      status.from_endpoint(endpoint, secret, status.AuthenticationPort),
    )
    == status.Reachable(response_kind: "access_accept")
}

pub fn healthcheck_marks_hardened_status_server_as_healthy_test() {
  assert healthcheck.evaluate(
      sample_endpoint(3799),
      status.Reachable(response_kind: "access_accept"),
    )
    == healthcheck.HealthReport(
      severity: healthcheck.Healthy,
      reason: "reachable_hardened:access_accept",
    )
}

pub fn radclient_renders_status_command_with_message_authenticator_test() {
  let endpoint = sample_endpoint(3799)

  assert radclient.render_status_command("radclient", endpoint)
    == Ok(
      radclient.RadclientCommand(
        binary: "radclient",
        arguments: ["127.0.0.1:3799", "status", "sharedsecret"],
        attributes: [
          "Packet-Type := Status-Server",
          "Message-Authenticator := 0x00",
        ],
      ),
    )
}

pub fn radclient_renders_disconnect_command_test() {
  let endpoint = sample_endpoint(3799)

  assert radclient.render_disconnect_command("radclient", endpoint, [
      "Acct-Session-Id := \"sess-1\"",
    ])
    == Ok(
      radclient.RadclientCommand(
        binary: "radclient",
        arguments: ["127.0.0.1:3799", "disconnect", "sharedsecret"],
        attributes: ["Acct-Session-Id := \"sess-1\""],
      ),
    )
}

fn sample_endpoint(port: Int) -> registry_types.NasEndpoint {
  registry_types.NasEndpoint(
    tenant_id: "tenant_a",
    endpoint_id: "edge_1",
    vendor: vendor_types.Cisco,
    transport: registry_types.Udp,
    coa_host: "127.0.0.1",
    coa_port: port,
    secret_ref: registry_types.InlineSecret(value: "sharedsecret"),
    timeout_ms: 1000,
    retry_profile_id: "default_udp",
    nas_ip_address: option.None,
    nas_identifier: option.Some("edge-1"),
    capabilities: capability.default_udp_capabilities(),
  )
}

fn endpoint_without_status() -> registry_types.NasEndpoint {
  registry_types.NasEndpoint(
    tenant_id: "tenant_a",
    endpoint_id: "edge_no_status",
    vendor: vendor_types.Cisco,
    transport: registry_types.Udp,
    coa_host: "127.0.0.1",
    coa_port: 3799,
    secret_ref: registry_types.InlineSecret(value: "sharedsecret"),
    timeout_ms: 1000,
    retry_profile_id: "default_udp",
    nas_ip_address: option.None,
    nas_identifier: option.Some("edge-1"),
    capabilities: registry_types.NasCapabilities(
      supports_coa: True,
      supports_disconnect: True,
      supports_status_server: False,
      requires_message_authenticator: True,
      requires_event_timestamp: True,
      supports_multi_session_match: False,
    ),
  )
}
