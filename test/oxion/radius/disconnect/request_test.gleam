import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/disconnect/request
import oxion/radius/profile/snapshot

pub fn disconnect_request_builds_from_suspend_command_test() {
  assert request.build_request(suspend_plan(), sample_selector())
    == Ok(request.DisconnectRequest(
      packet_type: "Disconnect-Request",
      reason: "overdue_collection",
      action_fingerprint: "fp:hard:0",
      session_selector: sample_selector(),
    ))
}

pub fn disconnect_request_rejects_non_disconnect_command_test() {
  assert request.build_request(change_package_plan(), sample_selector())
    == Error(request.UnsupportedCommand(command_name: "ChangePackage"))
}

fn sample_selector() -> snapshot.SessionSelector {
  snapshot.SessionSelector(
    username: option.Some("cust_001"),
    framed_ip: option.None,
    acct_session_id: option.None,
    nas_ip_address: option.Some("10.0.0.1"),
  )
}

fn suspend_plan() -> commands.CommandPlan {
  commands.CommandPlan(
    action_fingerprint: "fp:hard:0",
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

fn change_package_plan() -> commands.CommandPlan {
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
