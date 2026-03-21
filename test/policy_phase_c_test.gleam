import collection_dispatcher
import collection_idempotency
import collection_scheduler
import gleam/list
import gleam/option
import policy_evaluator
import policy_types

pub fn dispatcher_distinguishes_same_action_type_instances_test() {
  let matches = [
    policy_evaluator.StageMatch(stage_id: "soft_throttle", actions: [
      policy_types.EmitEvent(topic: "collection.first", payload: option.None),
      policy_types.EmitEvent(
        topic: "collection.second",
        payload: option.Some(
          policy_types.JsonObject([#("kind", policy_types.JsonString("harder"))]),
        ),
      ),
    ]),
  ]

  let collection_dispatcher.DispatchOutcome(
    executed: executed,
    skipped: skipped,
    fingerprints: fingerprints,
  ) =
    collection_dispatcher.dispatch_matches(
      "tnt_a",
      "sub_1",
      "inv_1",
      matches,
      [],
    )

  assert list.length(executed) == 2
  assert skipped == []
  assert list.length(fingerprints) == 2

  case executed {
    [first, second] -> {
      let collection_dispatcher.DispatchedAction(
        stage_id: _,
        action_name: _,
        action_identity: _,
        action_position: _,
        fingerprint: first_fp,
      ) = first
      let collection_dispatcher.DispatchedAction(
        stage_id: _,
        action_name: _,
        action_identity: _,
        action_position: _,
        fingerprint: second_fp,
      ) = second
      assert first_fp != second_fp
    }
    _ -> panic
  }
}

pub fn dispatcher_rerun_skips_same_action_instances_test() {
  let matches = [
    policy_evaluator.StageMatch(stage_id: "soft_throttle", actions: [
      policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
      policy_types.SendNotification(
        template_id: "collection.soft_throttle",
        include_payment_link: True,
        channels: [policy_types.Whatsapp],
      ),
    ]),
  ]

  let first =
    collection_dispatcher.dispatch_matches(
      "tnt_a",
      "sub_1",
      "inv_1",
      matches,
      [],
    )

  let collection_dispatcher.DispatchOutcome(
    executed: first_executed,
    skipped: first_skipped,
    fingerprints: fps,
  ) = first

  assert list.length(first_executed) == 2
  assert first_skipped == []

  let second =
    collection_dispatcher.dispatch_matches(
      "tnt_a",
      "sub_1",
      "inv_1",
      matches,
      fps,
    )

  let collection_dispatcher.DispatchOutcome(
    executed: second_executed,
    skipped: second_skipped,
    fingerprints: _,
  ) = second

  assert second_executed == []
  assert list.length(second_skipped) == 2
}

pub fn scheduler_rerun_no_duplicate_action_test() {
  let policy = sample_policy()
  let candidates = [
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
    ),
    collection_scheduler.OverdueCandidate(
      tenant_id: "tnt_a",
      subscriber_id: "sub_2",
      invoice_id: "inv_2",
      days_past_due: 21,
      invoice_status: "Overdue",
      operational_state: "normal",
      billing_plan: "postpaid",
      total_due_amount: 150_000,
      is_paid: False,
    ),
  ]

  let first = collection_scheduler.run(policy, candidates, [])
  let collection_scheduler.SchedulerRunResult(
    executed_total: first_executed,
    skipped_total: first_skipped,
    error_total: first_errors,
    fingerprints: fps,
    results: first_results,
  ) = first

  assert first_executed > 0
  assert first_skipped == 0
  assert first_errors == 0
  assert first_results != []

  let second = collection_scheduler.run(policy, candidates, fps)
  let collection_scheduler.SchedulerRunResult(
    executed_total: second_executed,
    skipped_total: second_skipped,
    error_total: second_errors,
    fingerprints: _,
    results: second_results,
  ) = second

  assert second_executed == 0
  assert second_skipped == first_executed
  assert second_errors == 0

  case second_results {
    [first_result, ..rest] -> {
      let collection_scheduler.CandidateExecutionResult(
        tenant_id: _,
        subscriber_id: _,
        invoice_id: _,
        matched_stage_ids: matched_stage_ids,
        executed_count: _,
        skipped_count: skipped_count,
        executed_actions: executed_actions,
        skipped_actions: skipped_actions,
        evaluation_error: evaluation_error,
      ) = first_result

      assert matched_stage_ids != []
      assert skipped_count > 0
      assert executed_actions == []
      assert skipped_actions != []
      assert evaluation_error == option.None
      assert rest != []
    }
    [] -> panic
  }
}

pub fn scheduler_exposes_scheduling_config_test() {
  assert collection_scheduler.scheduling_config(sample_policy())
    == collection_scheduler.SchedulerConfig(
      timezone: "Asia/Jakarta",
      evaluation_time: option.Some("00:15"),
    )
}

pub fn scheduler_surfaces_evaluation_errors_test() {
  let invalid_policy =
    policy_types.Policy(
      name: "invalid_eval",
      description: option.None,
      grace_days: 0,
      timezone: "Asia/Jakarta",
      context: option.None,
      stages: [
        policy_types.Stage(
          id: "invalid_when",
          priority: 10,
          condition: policy_types.Rule(
            field: policy_types.InvoiceStatus,
            op: policy_types.Gt,
            value: policy_types.ScalarValue(policy_types.StringValue("sent")),
            enabled: True,
          ),
          actions: [
            policy_types.EmitEvent(
              topic: "collection.invalid",
              payload: option.None,
            ),
          ],
          stop_on_match: True,
          notification_template: option.None,
          enabled: True,
        ),
      ],
    )

  let candidates = [
    collection_scheduler.OverdueCandidate(
      tenant_id: "tnt_a",
      subscriber_id: "sub_1",
      invoice_id: "inv_1",
      days_past_due: 10,
      invoice_status: "Overdue",
      operational_state: "normal",
      billing_plan: "postpaid",
      total_due_amount: 100_000,
      is_paid: False,
    ),
  ]

  let result = collection_scheduler.run(invalid_policy, candidates, [])

  assert result
    == collection_scheduler.SchedulerRunResult(
      executed_total: 0,
      skipped_total: 0,
      error_total: 1,
      fingerprints: [],
      results: [
        collection_scheduler.CandidateExecutionResult(
          tenant_id: "tnt_a",
          subscriber_id: "sub_1",
          invoice_id: "inv_1",
          matched_stage_ids: [],
          executed_count: 0,
          skipped_count: 0,
          executed_actions: [],
          skipped_actions: [],
          evaluation_error: option.Some(policy_evaluator.EvaluationError(
            code: "INVALID_WHEN_CONDITION",
            stage_id: "invalid_when",
            path: "stages[0].when.op",
            reason: "operator_not_allowed_for_string_field",
          )),
        ),
      ],
    )
}

pub fn retry_executor_succeeds_before_max_attempts_test() {
  let result =
    collection_idempotency.execute_with_retry_from_attempts(
      [
        Error("timeout"),
        Error("temporary_nak"),
        Ok("ack"),
      ],
      3,
    )

  assert result == Ok("ack")
}

pub fn retry_executor_fails_when_attempts_exhausted_test() {
  let result =
    collection_idempotency.execute_with_retry_from_attempts(
      [
        Error("timeout"),
        Error("timeout"),
        Error("timeout"),
      ],
      2,
    )

  assert result
    == Error(collection_idempotency.AttemptsExceeded(last_error: "timeout"))
}

pub fn retry_executor_rejects_invalid_max_attempts_test() {
  let result =
    collection_idempotency.execute_with_retry_from_attempts([Ok("ack")], 0)

  assert result == Error(collection_idempotency.InvalidMaxAttempts)
}

fn sample_policy() -> policy_types.Policy {
  let soft_stage =
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
    )

  let hard_stage =
    policy_types.Stage(
      id: "hard_suspend",
      priority: 20,
      condition: policy_types.Rule(
        field: policy_types.DaysPastDue,
        op: policy_types.Gte,
        value: policy_types.ScalarValue(policy_types.IntValue(21)),
        enabled: True,
      ),
      actions: [
        policy_types.SuspendService(reason: "overdue_collection"),
        policy_types.SendNotification(
          template_id: "collection.hard_suspend",
          include_payment_link: True,
          channels: [policy_types.Whatsapp],
        ),
      ],
      stop_on_match: True,
      notification_template: option.Some("collection.hard_suspend"),
      enabled: True,
    )

  policy_types.Policy(
    name: "default_collection",
    description: option.Some("Default overdue policy"),
    grace_days: 0,
    timezone: "Asia/Jakarta",
    context: option.Some(policy_types.PolicyContextConfig(
      evaluation_time: option.Some("00:15"),
      payment_link_mode: option.None,
      payment_link_base_url: option.None,
      payment_link_ttl_minutes: option.None,
    )),
    stages: [hard_stage, soft_stage],
  )
}
