import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/execution
import oxion/radius/coa/request
import oxion/radius/coa/response
import oxion/radius/coa/result
import oxion/radius/coa/retry
import oxion/radius/coa/transport
import oxion/radius/profile/snapshot
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

@external(erlang, "oxion_radius_mock_transport_ffi", "start_ack_server")
fn start_ack_server(secret: String) -> Result(Int, String)

@external(erlang, "oxion_radius_mock_transport_ffi", "start_nak_server")
fn start_nak_server(
  secret: String,
  error_cause: Int,
  message: String,
) -> Result(Int, String)

@external(erlang, "oxion_radius_mock_transport_ffi", "start_bad_auth_server")
fn start_bad_auth_server(secret: String) -> Result(Int, String)

pub fn transport_roundtrip_ack_live_udp_test() {
  let secret = "sharedsecret"
  let port = case start_ack_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }
  let request_value =
    request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_soft_throttle",
      action_fingerprint: "fp:live:ack",
      session_selector: sample_selector(),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "class",
          value: "throttled_due_overdue",
        ),
      ],
      disconnect_hint: False,
    )

  assert transport.roundtrip(
      request_value,
      vendor_types.Cisco,
      "bw_4mbps",
      transport.CoaTransportConfig(
        host: "127.0.0.1",
        port: port,
        secret: secret,
        timeout_ms: 1000,
      ),
    )
    == response.Ack(nas: "127.0.0.1", applied_target: "bw_4mbps")
}

pub fn transport_roundtrip_nak_live_udp_test() {
  let secret = "sharedsecret"
  let port = case start_nak_server(secret, 401, "unsupported attribute") {
    Ok(port) -> port
    Error(_) -> panic
  }
  let request_value =
    request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_soft_throttle",
      action_fingerprint: "fp:live:nak",
      session_selector: sample_selector(),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "class",
          value: "throttled_due_overdue",
        ),
      ],
      disconnect_hint: False,
    )

  assert transport.roundtrip(
      request_value,
      vendor_types.Cisco,
      "bw_4mbps",
      transport.CoaTransportConfig(
        host: "127.0.0.1",
        port: port,
        secret: secret,
        timeout_ms: 1000,
      ),
    )
    == response.Nak(
      nas: "127.0.0.1",
      error_code: "error_cause_401",
      error_message: "unsupported attribute",
    )
}

pub fn transport_rejects_bad_response_authenticator_test() {
  let secret = "sharedsecret"
  let port = case start_bad_auth_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }
  let request_value =
    request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_soft_throttle",
      action_fingerprint: "fp:live:bad-auth",
      session_selector: sample_selector(),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "class",
          value: "throttled_due_overdue",
        ),
      ],
      disconnect_hint: False,
    )

  assert transport.roundtrip(
      request_value,
      vendor_types.Cisco,
      "bw_4mbps",
      transport.CoaTransportConfig(
        host: "127.0.0.1",
        port: port,
        secret: secret,
        timeout_ms: 1000,
      ),
    )
    == response.Malformed(reason: "response_authenticator_mismatch")
}

pub fn execution_live_transport_ack_integration_test() {
  let secret = "sharedsecret"
  let port = case start_ack_server(secret) {
    Ok(port) -> port
    Error(_) -> panic
  }
  let selector = sample_selector()

  assert execution.send_coa_live(
      throttle_plan(),
      vendor_types.Cisco,
      selector,
      option.Some(normal_snapshot(selector)),
      sample_registry(),
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      transport.CoaTransportConfig(
        host: "127.0.0.1",
        port: port,
        secret: secret,
        timeout_ms: 1000,
      ),
    )
    == result.Ack(applied_target: "bw_4mbps", retries: 0)
}

fn throttle_plan() -> commands.CommandPlan {
  commands.CommandPlan(
    action_fingerprint: "fp:soft:0",
    stage_id: "soft_throttle",
    action_name: "apply_bandwidth_profile",
    route: commands.RadiusRoute,
    command: commands.ChangePackage(
      service_id: "svc_1",
      target_profile_id: "bw_4mbps",
    ),
    target_state: "throttled_due_overdue",
  )
}

fn sample_registry() -> List(types.ProfileDefinition) {
  [
    types.ProfileDefinition(
      profile_id: "bw_4mbps",
      service_profile_id: "bw_4mbps",
      download_kbps: 4096,
      upload_kbps: 4096,
    ),
    types.ProfileDefinition(
      profile_id: "svc_home_100m",
      service_profile_id: "svc_home_100m",
      download_kbps: 102_400,
      upload_kbps: 102_400,
    ),
  ]
}

fn sample_selector() -> snapshot.SessionSelector {
  snapshot.SessionSelector(
    username: option.Some("cust_001"),
    framed_ip: option.Some("10.10.20.5"),
    acct_session_id: option.None,
    nas_ip_address: option.None,
  )
}

fn normal_snapshot(
  selector: snapshot.SessionSelector,
) -> snapshot.ActiveProfileSnapshot {
  snapshot.ActiveProfileSnapshot(
    service_id: "svc_1",
    selector: selector,
    profile_id: option.Some("svc_home_100m"),
    attributes: [
      vendor_types.RadiusAttribute(
        name: "cisco_avpair.service_profile",
        value: "svc_home_100m",
      ),
      vendor_types.RadiusAttribute(
        name: "cisco_avpair.qos_down",
        value: "102400",
      ),
      vendor_types.RadiusAttribute(name: "cisco_avpair.qos_up", value: "102400"),
      vendor_types.RadiusAttribute(name: "class", value: "normal"),
    ],
    session_active: True,
  )
}
