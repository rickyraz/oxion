import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/replay
import oxion/radius/coa/retry
import oxion/radius/coa/transport as shared_transport
import oxion/radius/disconnect/execution
import oxion/radius/disconnect/request
import oxion/radius/disconnect/response
import oxion/radius/disconnect/result
import oxion/radius/disconnect/transport
import oxion/radius/packet
import oxion/radius/profile/snapshot
import oxion/radius/registry/capability
import oxion/radius/registry/types as registry_types
import oxion/radius/session/types as session_types
import oxion/radius/vendor/types as vendor_types

@external(erlang, "oxion_radius_mock_transport_ffi", "start_ack_server")
fn start_ack_server(secret: String) -> Result(Int, String)

@external(erlang, "oxion_radius_mock_transport_ffi", "start_nak_server")
fn start_nak_server(
  secret: String,
  error_cause: Int,
  message: String,
) -> Result(Int, String)

pub fn disconnect_transport_roundtrip_ack_live_udp_test() {
  let secret = "sharedsecret"
  let port = case start_ack_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }

  assert transport.roundtrip(
      disconnect_request(),
      test_transport_config(port, secret),
    )
    == response.Ack(nas: "127.0.0.1")
}

pub fn disconnect_transport_roundtrip_nak_live_udp_test() {
  let secret = "sharedsecret"
  let port = case start_nak_server(secret, 503, "session context missing") {
    Ok(port) -> port
    Error(_) -> panic
  }

  assert transport.roundtrip(
      disconnect_request(),
      test_transport_config(port, secret),
    )
    == response.Nak(
      nas: "127.0.0.1",
      error_code: "error_cause_503",
      error_message: "session context missing",
    )
}

pub fn disconnect_execution_managed_runtime_ack_test() {
  let secret = "sharedsecret"
  let port = case start_ack_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }

  assert execution.send_disconnect_live_managed(
      suspend_plan(),
      vendor_types.Cisco,
      session_types.SessionLookup(
        tenant_id: "tenant_a",
        service_id: "svc_1",
        username: option.Some("cust_001"),
        acct_session_id: option.None,
        framed_ip: option.None,
      ),
      60,
      [sample_endpoint(port)],
      [sample_active_session()],
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      1_710_000_000,
    )
    == result.Ack(retries: 0)
}

pub fn disconnect_execution_managed_runtime_replay_rejects_duplicate_test() {
  let secret = "sharedsecret"
  let port = case start_ack_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }
  let replay_window = replay.ReplayWindow(max_age_seconds: 30, max_entries: 10)

  let #(first_result, cache_after_first) =
    execution.send_disconnect_live_managed_with_replay(
      suspend_plan(),
      vendor_types.Cisco,
      session_types.SessionLookup(
        tenant_id: "tenant_a",
        service_id: "svc_1",
        username: option.Some("cust_001"),
        acct_session_id: option.None,
        framed_ip: option.None,
      ),
      60,
      [sample_endpoint(port)],
      [sample_active_session()],
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      replay.new(),
      replay_window,
      1_710_000_000,
    )

  assert first_result == result.Ack(retries: 0)

  let #(second_result, cache_after_second) =
    execution.send_disconnect_live_managed_with_replay(
      suspend_plan(),
      vendor_types.Cisco,
      session_types.SessionLookup(
        tenant_id: "tenant_a",
        service_id: "svc_1",
        username: option.Some("cust_001"),
        acct_session_id: option.None,
        framed_ip: option.None,
      ),
      60,
      [sample_endpoint(port)],
      [sample_active_session()],
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      cache_after_first,
      replay_window,
      1_710_000_000,
    )

  assert second_result == result.ReplayRejected(reason: "duplicate_request")
  assert cache_after_second == cache_after_first
}

fn disconnect_request() -> request.DisconnectRequest {
  request.DisconnectRequest(
    packet_type: "Disconnect-Request",
    reason: "overdue_collection",
    action_fingerprint: "fp:disconnect:1",
    session_selector: session_selector(),
  )
}

fn session_selector() -> snapshot.SessionSelector {
  snapshot.SessionSelector(
    username: option.Some("cust_001"),
    framed_ip: option.Some("10.10.20.5"),
    acct_session_id: option.Some("sess-1"),
    nas_ip_address: option.None,
  )
}

fn suspend_plan() -> commands.CommandPlan {
  commands.CommandPlan(
    action_fingerprint: "fp:disconnect:1",
    stage_id: "hard_suspend",
    action_name: "suspend_service",
    route: commands.RadiusRoute,
    command: commands.SuspendService(
      service_id: "svc_1",
      reason: "overdue_collection",
    ),
    target_state: "suspended_due_overdue",
  )
}

fn test_transport_config(
  port: Int,
  secret: String,
) -> shared_transport.CoaTransportConfig {
  shared_transport.CoaTransportConfig(
    host: "127.0.0.1",
    port: port,
    secret: secret,
    timeout_ms: 1000,
    request_security: packet.PacketSecurityConfig(
      message_authenticator: True,
      event_timestamp: option.Some(1_710_000_000),
    ),
    require_message_authenticator_response: True,
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

fn sample_active_session() -> session_types.ActiveSession {
  session_types.ActiveSession(
    tenant_id: "tenant_a",
    service_id: "svc_1",
    username: option.Some("cust_001"),
    acct_session_id: option.Some("sess-1"),
    framed_ip: option.Some("10.10.20.5"),
    nas_ip_address: option.None,
    nas_identifier: option.Some("edge-1"),
    active_profile_id: option.Some("svc_home_100m"),
    attributes: [
      vendor_types.RadiusAttribute(name: "class", value: "normal"),
    ],
    last_accounting_epoch_seconds: 1_709_999_980,
    session_active: True,
  )
}
