import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/execution
import oxion/radius/coa/response
import oxion/radius/coa/result
import oxion/radius/coa/retry
import oxion/radius/profile/snapshot
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

pub fn execution_returns_idempotent_skip_when_target_is_active_test() {
  let plan = throttle_plan()
  let registry = sample_registry()
  let selector = sample_selector()
  let active_snapshot =
    option.Some(snapshot.ActiveProfileSnapshot(
      service_id: "svc_1",
      selector: selector,
      profile_id: option.Some("bw_4mbps"),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "class",
          value: "throttled_due_overdue",
        ),
        vendor_types.RadiusAttribute(name: "cisco.qos_up", value: "4096"),
        vendor_types.RadiusAttribute(
          name: "cisco.service_profile",
          value: "bw_4mbps",
        ),
        vendor_types.RadiusAttribute(name: "cisco.qos_down", value: "4096"),
      ],
      session_active: True,
    ))

  assert execution.send_coa_if_needed(
      plan,
      vendor_types.Cisco,
      selector,
      active_snapshot,
      registry,
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      [response.Ack(nas: "bng-edge-01", applied_target: "bw_4mbps")],
    )
    == result.IdempotentSkip(reason: "target_profile_already_active")
}

pub fn execution_retries_timeout_then_ack_test() {
  let plan = throttle_plan()
  let registry = sample_registry()
  let selector = sample_selector()
  let active_snapshot = option.Some(normal_snapshot(selector))

  assert execution.send_coa_if_needed(
      plan,
      vendor_types.Cisco,
      selector,
      active_snapshot,
      registry,
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      [
        response.Timeout,
        response.Ack(nas: "bng-edge-01", applied_target: "bw_4mbps"),
      ],
    )
    == result.Ack(applied_target: "bw_4mbps", retries: 1)
}

pub fn execution_returns_nak_without_retry_test() {
  let plan = throttle_plan()
  let registry = sample_registry()
  let selector = sample_selector()
  let active_snapshot = option.Some(normal_snapshot(selector))

  assert execution.send_coa_if_needed(
      plan,
      vendor_types.Cisco,
      selector,
      active_snapshot,
      registry,
      retry.RetryPolicy(max_attempts: 3, backoff_ms: [100, 250, 500]),
      [
        response.Nak(
          nas: "bng-edge-01",
          error_code: "unsupported_attribute",
          error_message: "class is invalid",
        ),
        response.Ack(nas: "bng-edge-01", applied_target: "bw_4mbps"),
      ],
    )
    == result.Nak(
      code: "unsupported_attribute",
      message: "class is invalid",
      retries: 0,
    )
}

pub fn execution_requires_active_snapshot_test() {
  let plan = throttle_plan()
  let registry = sample_registry()
  let selector = sample_selector()

  assert execution.send_coa_if_needed(
      plan,
      vendor_types.Cisco,
      selector,
      option.None,
      registry,
      retry.RetryPolicy(max_attempts: 2, backoff_ms: [100, 250]),
      [response.Ack(nas: "bng-edge-01", applied_target: "bw_4mbps")],
    )
    == result.SnapshotUnavailable(reason: "active_snapshot_missing")
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
        name: "cisco.service_profile",
        value: "svc_home_100m",
      ),
      vendor_types.RadiusAttribute(name: "cisco.qos_down", value: "102400"),
      vendor_types.RadiusAttribute(name: "cisco.qos_up", value: "102400"),
      vendor_types.RadiusAttribute(name: "class", value: "normal"),
    ],
    session_active: True,
  )
}
