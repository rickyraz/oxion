import oxion/orchestration/collection/commands
import oxion/orchestration/collection/olt_guard

pub fn olt_guard_blocks_olt_route_for_radius_only_test() {
  let plan =
    commands.CommandPlan(
      action_fingerprint: "fp:olt:0",
      stage_id: "hard_suspend",
      action_name: "suspend_service",
      route: commands.OltRoute,
      command: commands.SuspendService(service_id: "svc_1", reason: "manual"),
      target_state: "suspended_due_overdue",
    )

  assert olt_guard.validate_plan(commands.RadiusOnly, plan)
    == Error(olt_guard.OltMutationBlocked(
      reason: "radius_only_blocks_olt_mutation",
    ))
}

pub fn olt_guard_rejects_unknown_target_test() {
  let plan =
    commands.CommandPlan(
      action_fingerprint: "fp:rad:0",
      stage_id: "soft_throttle",
      action_name: "apply_bandwidth_profile",
      route: commands.RadiusRoute,
      command: commands.ChangePackage(
        service_id: "svc_1",
        target_profile_id: "bw_4mbps",
      ),
      target_state: "throttled_due_overdue",
    )

  assert olt_guard.validate_plan(
      commands.CustomEnforcementTarget(value: "legacy_bridge"),
      plan,
    )
    == Error(olt_guard.UnknownEnforcementTarget(value: "legacy_bridge"))
}
