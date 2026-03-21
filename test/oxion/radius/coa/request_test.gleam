import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/request
import oxion/radius/profile/snapshot
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

pub fn request_builds_suspend_packet_with_disconnect_hint_test() {
  let plan =
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
  let selector =
    snapshot.SessionSelector(
      username: option.Some("cust_001"),
      framed_ip: option.None,
      acct_session_id: option.None,
      nas_ip_address: option.None,
    )
  let target =
    types.ResolvedTarget(target_id: "suspend", attributes: [
      vendor_types.RadiusAttribute(
        name: "api.policy.access_action",
        value: "suspend",
      ),
    ])

  assert request.build_request(plan, selector, target)
    == Ok(request.CoaRequest(
      packet_type: "CoA-Request",
      reason: "collection_hard_suspend",
      action_fingerprint: "fp:hard:0",
      session_selector: selector,
      attributes: [
        vendor_types.RadiusAttribute(
          name: "api.policy.access_action",
          value: "suspend",
        ),
      ],
      disconnect_hint: True,
    ))
}

pub fn request_rejects_missing_session_selector_test() {
  let plan =
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
  let selector =
    snapshot.SessionSelector(
      username: option.None,
      framed_ip: option.None,
      acct_session_id: option.None,
      nas_ip_address: option.None,
    )
  let target =
    types.ResolvedTarget(target_id: "bw_4mbps", attributes: [
      vendor_types.RadiusAttribute(
        name: "class",
        value: "throttled_due_overdue",
      ),
    ])

  assert request.build_request(plan, selector, target)
    == Error(request.MissingSessionSelector)
}
