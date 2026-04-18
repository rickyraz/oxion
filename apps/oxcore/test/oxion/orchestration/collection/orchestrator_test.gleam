import gleam/list
import gleam/option
import oxion/collection/dispatcher as collection_dispatcher
import oxion/orchestration/collection/audit
import oxion/orchestration/collection/commands
import oxion/orchestration/collection/orchestrator
import oxion/orchestration/collection/outcome
import oxion/policy/types as policy_types
import oxion/radius/coa/result as coa_result
import oxion/radius/disconnect/result as disconnect_result

pub fn orchestrator_maps_runtime_actions_to_commands_and_side_effects_test() {
  let service =
    commands.ServiceIdentity(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
    )

  let executed_actions = [
    collection_dispatcher.DispatchedAction(
      stage_id: "soft_throttle",
      action_name: "apply_bandwidth_profile",
      action_identity: "apply_bandwidth_profile:bw_4mbps",
      action_position: 0,
      fingerprint: "fp:soft:0",
      action: policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
    ),
    collection_dispatcher.DispatchedAction(
      stage_id: "soft_throttle",
      action_name: "send_notification",
      action_identity: "send_notification:collection.soft:true:whatsapp",
      action_position: 1,
      fingerprint: "fp:soft:1",
      action: policy_types.SendNotification(
        template_id: "collection.soft",
        include_payment_link: True,
        channels: [policy_types.Whatsapp],
      ),
    ),
  ]

  case
    orchestrator.plan_candidate(
      service,
      executed_actions,
      option.None,
      commands.RadiusOnly,
    )
  {
    Ok(orchestrator.OrchestrationPlan(
      commands: command_plans,
      side_effects: side_effects,
    )) -> {
      assert list.length(command_plans) == 1
      assert list.length(side_effects) == 1

      case command_plans {
        [
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
          ),
        ] -> Nil
        _ -> panic
      }

      case side_effects {
        [
          commands.NotificationPlan(
            stage_id: "soft_throttle",
            template_id: "collection.soft",
            include_payment_link: True,
            channels: [policy_types.Whatsapp],
            action_fingerprint: "fp:soft:1",
          ),
        ] -> Nil
        _ -> panic
      }
    }
    Error(_) -> panic
  }
}

pub fn orchestrator_restore_requires_original_profile_test() {
  let service =
    commands.ServiceIdentity(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
    )

  let executed_actions = [
    collection_dispatcher.DispatchedAction(
      stage_id: "restore",
      action_name: "restore_service",
      action_identity: "restore_service",
      action_position: 0,
      fingerprint: "fp:restore:0",
      action: policy_types.RestoreService,
    ),
  ]

  assert orchestrator.plan_candidate(
      service,
      executed_actions,
      option.None,
      commands.RadiusOnly,
    )
    == Error(orchestrator.MissingOriginalProfile)
}

pub fn orchestrator_rejects_conflicting_target_states_test() {
  let service =
    commands.ServiceIdentity(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
    )

  let executed_actions = [
    collection_dispatcher.DispatchedAction(
      stage_id: "soft_throttle",
      action_name: "apply_bandwidth_profile",
      action_identity: "apply_bandwidth_profile:bw_4mbps",
      action_position: 0,
      fingerprint: "fp:soft:0",
      action: policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
    ),
    collection_dispatcher.DispatchedAction(
      stage_id: "hard_suspend",
      action_name: "suspend_service",
      action_identity: "suspend_service:overdue_collection",
      action_position: 0,
      fingerprint: "fp:hard:0",
      action: policy_types.SuspendService(reason: "overdue_collection"),
    ),
  ]

  assert orchestrator.plan_candidate(
      service,
      executed_actions,
      option.None,
      commands.RadiusOnly,
    )
    == Error(orchestrator.ConflictingTargetState(
      existing: "throttled_due_overdue",
      incoming: "suspended_due_overdue",
    ))
}

pub fn audit_entry_tracks_radius_outcome_test() {
  let service =
    commands.ServiceIdentity(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
    )
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
  let command_outcome =
    outcome.from_radius_execution(
      plan,
      coa_result.Ack(applied_target: "bw_4mbps", retries: 1),
    )

  assert audit.from_command_outcome(service, plan, command_outcome)
    == audit.AuditEntry(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
      stage_id: "soft_throttle",
      action_name: "apply_bandwidth_profile",
      action_fingerprint: "fp:soft:0",
      command_name: "ChangePackage",
      target_state: "throttled_due_overdue",
      result_type: "success",
      reason: option.None,
      retry_count: 1,
    )
}

pub fn outcome_maps_disconnect_execution_contract_test() {
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

  assert outcome.from_disconnect_execution(
      plan,
      disconnect_result.Ack(retries: 1),
    )
    == outcome.CommandOutcome(
      action_fingerprint: "fp:hard:0",
      stage_id: "hard_suspend",
      action_name: "suspend_service",
      target_state: "suspended_due_overdue",
      status: outcome.Succeeded,
      reason: option.None,
      retry_count: 1,
    )

  assert outcome.from_disconnect_execution(
      plan,
      disconnect_result.Nak("503", "session context missing", 0),
    )
    == outcome.CommandOutcome(
      action_fingerprint: "fp:hard:0",
      stage_id: "hard_suspend",
      action_name: "suspend_service",
      target_state: "suspended_due_overdue",
      status: outcome.Failed,
      reason: option.Some("503:session context missing"),
      retry_count: 0,
    )
}
