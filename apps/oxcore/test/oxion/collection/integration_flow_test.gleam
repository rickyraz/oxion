import gleam/option
import oxion/collection/scheduler as collection_scheduler
import oxion/orchestration/collection/audit as collection_audit
import oxion/orchestration/collection/commands as collection_commands
import oxion/orchestration/collection/orchestrator as collection_orchestrator
import oxion/orchestration/collection/outcome as collection_outcome
import oxion/policy/types as policy_types
import oxion/radius/coa/result as coa_result

pub fn collection_flow_policy_to_audit_is_deterministic_and_idempotent_test() {
  let service =
    collection_commands.ServiceIdentity(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
    )
  let candidate =
    collection_scheduler.OverdueCandidate(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      invoice_id: "inv_1",
      days_past_due: 8,
      invoice_status: "Overdue",
      operational_state: "normal",
      billing_plan: "postpaid",
      total_due_amount: 100_000,
      is_paid: False,
    )

  let first_run = collection_scheduler.run(sample_policy(), [candidate], [])

  assert first_run.executed_total == 2
  assert first_run.skipped_total == 0
  assert first_run.error_total == 0

  let #(executed_actions, apply_fingerprint, notification_fingerprint) = case
    first_run.results
  {
    [
      collection_scheduler.CandidateExecutionResult(
        tenant_id: "tnt_a",
        subscriber_id: "sub_1",
        invoice_id: "inv_1",
        matched_stage_ids: ["soft_throttle"],
        executed_count: 2,
        skipped_count: 0,
        executed_actions: executed_actions,
        skipped_actions: [],
        evaluation_error: option.None,
      ),
    ] ->
      case executed_actions {
        [apply_action, notify_action] -> {
          let apply_fingerprint = apply_action.fingerprint
          let notification_fingerprint = notify_action.fingerprint
          #(executed_actions, apply_fingerprint, notification_fingerprint)
        }
        _ -> panic
      }
    _ -> panic
  }

  let plan = case
    collection_orchestrator.plan_candidate(
      service,
      executed_actions,
      option.None,
      collection_commands.RadiusOnly,
    )
  {
    Ok(plan) -> plan
    Error(_) -> panic
  }

  assert plan.side_effects
    == [
      collection_commands.NotificationPlan(
        stage_id: "soft_throttle",
        template_id: "collection.soft_throttle",
        include_payment_link: True,
        channels: [policy_types.Whatsapp],
        action_fingerprint: notification_fingerprint,
      ),
    ]

  let command_plan = case plan.commands {
    [command_plan] -> command_plan
    _ -> panic
  }

  let command_outcome =
    collection_outcome.from_radius_execution(
      command_plan,
      coa_result.Ack(applied_target: "bw_4mbps", retries: 1),
    )

  assert collection_audit.from_command_outcome(
      service,
      command_plan,
      command_outcome,
    )
    == collection_audit.AuditEntry(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      service_id: "svc_1",
      invoice_id: "inv_1",
      stage_id: "soft_throttle",
      action_name: "apply_bandwidth_profile",
      action_fingerprint: apply_fingerprint,
      command_name: "ChangePackage",
      target_state: "throttled_due_overdue",
      result_type: "success",
      reason: option.None,
      retry_count: 1,
    )

  let second_run =
    collection_scheduler.run(
      sample_policy(),
      [candidate],
      first_run.fingerprints,
    )

  assert second_run.executed_total == 0
  assert second_run.skipped_total == 2
  assert second_run.error_total == 0

  case second_run.results {
    [
      collection_scheduler.CandidateExecutionResult(
        tenant_id: "tnt_a",
        subscriber_id: "sub_1",
        invoice_id: "inv_1",
        matched_stage_ids: ["soft_throttle"],
        executed_count: 0,
        skipped_count: 2,
        executed_actions: [],
        skipped_actions: _,
        evaluation_error: option.None,
      ),
    ] -> Nil
    _ -> panic
  }
}

fn sample_policy() -> policy_types.Policy {
  policy_types.Policy(
    name: "integration_collection",
    description: option.Some("Integration flow policy"),
    grace_days: 0,
    timezone: "Asia/Jakarta",
    context: option.Some(policy_types.PolicyContextConfig(
      evaluation_time: option.Some("00:15"),
      payment_link_mode: option.None,
      payment_link_base_url: option.None,
      payment_link_ttl_minutes: option.None,
    )),
    stages: [
      policy_types.Stage(
        id: "soft_throttle",
        priority: 10,
        condition: policy_types.All([
          policy_types.Rule(
            field: policy_types.DaysPastDue,
            op: policy_types.Gte,
            value: policy_types.ScalarValue(policy_types.IntValue(6)),
            enabled: True,
          ),
          policy_types.Rule(
            field: policy_types.DaysPastDue,
            op: policy_types.Lte,
            value: policy_types.ScalarValue(policy_types.IntValue(20)),
            enabled: True,
          ),
        ]),
        actions: [
          policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
          policy_types.SendNotification(
            template_id: "collection.soft_throttle",
            include_payment_link: True,
            channels: [policy_types.Whatsapp],
          ),
        ],
        stop_on_match: True,
        notification_template: option.Some("collection.soft_throttle"),
        enabled: True,
      ),
    ],
  )
}
