import gleam/option
import oxion/policy/evaluator as policy_evaluator
import oxion/policy/simulator as policy_simulator
import oxion/policy/types as policy_types
import oxion/policy/validator as policy_validator

pub fn policy_validator_valid_policy_test() {
  let policy = sample_policy(0)
  assert policy_validator.validate_policy(policy) == Ok(Nil)
}

pub fn policy_validator_rejects_empty_stage_list_test() {
  let policy =
    policy_types.Policy(
      name: "invalid",
      description: option.None,
      grace_days: 0,
      timezone: "Asia/Jakarta",
      context: option.None,
      stages: [],
    )

  case policy_validator.validate_policy(policy) {
    Error([first, ..rest]) -> {
      assert first
        == policy_validator.ValidationError(
          code: policy_validator.MissingStagesCode,
          path: "stages",
          reason: "policy_must_define_at_least_one_stage",
        )
      assert rest == []
    }
    _ -> panic
  }
}

pub fn policy_validator_rejects_invalid_timezone_and_stage_actions_test() {
  let invalid_stage =
    policy_types.Stage(
      id: "bad stage",
      priority: 0,
      condition: policy_types.Rule(
        field: policy_types.DaysPastDue,
        op: policy_types.Gte,
        value: policy_types.ScalarValue(policy_types.IntValue(6)),
        enabled: True,
      ),
      actions: [],
      stop_on_match: True,
      notification_template: option.None,
      enabled: True,
    )

  let policy =
    policy_types.Policy(
      name: "invalid",
      description: option.None,
      grace_days: -1,
      timezone: "Jakarta",
      context: option.None,
      stages: [invalid_stage],
    )

  case policy_validator.validate_policy(policy) {
    Error(errors) -> {
      assert errors
        == [
          policy_validator.ValidationError(
            code: policy_validator.InvalidGraceDaysCode,
            path: "grace_days",
            reason: "grace_days_must_be_non_negative",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidTimezoneCode,
            path: "timezone",
            reason: "timezone_must_match_iana_like_pattern",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidStageIdCode,
            path: "stages[0].id",
            reason: "stage_id_must_match_schema_pattern",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidStagePriorityCode,
            path: "stages[0].priority",
            reason: "stage_priority_out_of_range",
          ),
          policy_validator.ValidationError(
            code: policy_validator.MissingActionsCode,
            path: "stages[0].actions",
            reason: "stage_must_define_at_least_one_action",
          ),
        ]
    }
    Ok(_) -> panic
  }
}

pub fn policy_validator_rejects_invalid_action_payload_and_context_test() {
  let invalid_stage =
    policy_types.Stage(
      id: "invalid_payload",
      priority: 10,
      condition: policy_types.Rule(
        field: policy_types.DaysPastDue,
        op: policy_types.Gte,
        value: policy_types.ScalarValue(policy_types.IntValue(6)),
        enabled: True,
      ),
      actions: [
        policy_types.EmitEvent(
          topic: "evt.invalid_payload",
          payload: option.Some(policy_types.JsonString("bad")),
        ),
        policy_types.RunPluginHook(
          plugin_id: "bad_plugin",
          hook: "",
          payload: option.Some(policy_types.JsonInt(42)),
        ),
      ],
      stop_on_match: True,
      notification_template: option.None,
      enabled: True,
    )

  let policy =
    policy_types.Policy(
      name: "invalid_payload",
      description: option.None,
      grace_days: 0,
      timezone: "Asia/Jakarta",
      context: option.Some(policy_types.PolicyContextConfig(
        evaluation_time: option.Some("25:00"),
        payment_link_mode: option.Some(policy_types.SignedPaymentLink),
        payment_link_base_url: option.Some("not-a-uri"),
        payment_link_ttl_minutes: option.Some(0),
      )),
      stages: [invalid_stage],
    )

  case policy_validator.validate_policy(policy) {
    Error(errors) -> {
      assert errors
        == [
          policy_validator.ValidationError(
            code: policy_validator.InvalidContextConfigCode,
            path: "context.evaluation_time",
            reason: "evaluation_time_must_be_hh_mm",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidContextConfigCode,
            path: "context.payment_link_base_url",
            reason: "payment_link_base_url_must_be_uri_like",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidContextConfigCode,
            path: "context.payment_link_ttl_minutes",
            reason: "payment_link_ttl_minutes_out_of_range",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidActionConfigCode,
            path: "stages[0].actions[0].payload",
            reason: "payload_must_be_json_object",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidActionConfigCode,
            path: "stages[0].actions[1].plugin_id",
            reason: "plugin_id_must_match_schema_pattern",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidActionConfigCode,
            path: "stages[0].actions[1].hook",
            reason: "plugin_hook_out_of_range",
          ),
          policy_validator.ValidationError(
            code: policy_validator.InvalidActionConfigCode,
            path: "stages[0].actions[1].payload",
            reason: "payload_must_be_json_object",
          ),
        ]
    }
    Ok(_) -> panic
  }
}

pub fn policy_evaluator_priority_and_tie_break_test() {
  let stage_b =
    policy_types.Stage(
      id: "b_stage",
      priority: 10,
      condition: days_between_condition(6, 20),
      actions: [
        policy_types.EmitEvent(topic: "collection.b", payload: option.None),
      ],
      stop_on_match: False,
      notification_template: option.None,
      enabled: True,
    )

  let stage_a =
    policy_types.Stage(
      id: "a_stage",
      priority: 10,
      condition: days_between_condition(6, 20),
      actions: [
        policy_types.EmitEvent(topic: "collection.a", payload: option.None),
      ],
      stop_on_match: False,
      notification_template: option.None,
      enabled: True,
    )

  let policy =
    policy_types.Policy(
      name: "tie-break",
      description: option.None,
      grace_days: 0,
      timezone: "Asia/Jakarta",
      context: option.None,
      stages: [stage_b, stage_a],
    )

  case policy_evaluator.evaluate(policy, sample_context(10)) {
    Ok(policy_evaluator.EvaluationResult(matches: matches)) -> {
      assert matches
        == [
          policy_evaluator.StageMatch(stage_id: "a_stage", actions: [
            policy_types.EmitEvent(topic: "collection.a", payload: option.None),
          ]),
          policy_evaluator.StageMatch(stage_id: "b_stage", actions: [
            policy_types.EmitEvent(topic: "collection.b", payload: option.None),
          ]),
        ]
    }
    Error(_) -> panic
  }
}

pub fn policy_evaluator_stop_on_match_test() {
  let policy = sample_policy(0)

  case policy_evaluator.evaluate(policy, sample_context(8)) {
    Ok(policy_evaluator.EvaluationResult(matches: matches)) -> {
      assert matches
        == [
          policy_evaluator.StageMatch(stage_id: "soft_throttle", actions: [
            policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
            policy_types.SendNotification(
              template_id: "collection.soft_throttle",
              include_payment_link: True,
              channels: [policy_types.Whatsapp, policy_types.Email],
            ),
          ]),
        ]
    }
    Error(_) -> panic
  }
}

pub fn policy_evaluator_returns_structured_error_for_invalid_when_test() {
  let invalid_stage =
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
    )

  let policy =
    policy_types.Policy(
      name: "invalid_when",
      description: option.None,
      grace_days: 0,
      timezone: "Asia/Jakarta",
      context: option.None,
      stages: [invalid_stage],
    )

  assert policy_evaluator.evaluate(policy, sample_context(10))
    == Error(policy_evaluator.EvaluationError(
      code: "INVALID_WHEN_CONDITION",
      stage_id: "invalid_when",
      path: "stages[0].when.op",
      reason: "operator_not_allowed_for_string_field",
    ))
}

pub fn policy_simulator_range_with_actions_and_reason_test() {
  let policy = sample_policy(0)

  case policy_simulator.simulate_days(policy, sample_context(0), 20, 22) {
    Ok(rows) -> {
      assert rows
        == [
          policy_simulator.SimulationRow(day: 20, matches: [
            policy_simulator.SimulationMatch(
              stage_id: "soft_throttle",
              actions: [
                policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
                policy_types.SendNotification(
                  template_id: "collection.soft_throttle",
                  include_payment_link: True,
                  channels: [policy_types.Whatsapp, policy_types.Email],
                ),
              ],
              reason: "when_condition_matched",
            ),
          ]),
          policy_simulator.SimulationRow(day: 21, matches: [
            policy_simulator.SimulationMatch(
              stage_id: "hard_suspend",
              actions: [
                policy_types.SuspendService(reason: "overdue_collection"),
                policy_types.SendNotification(
                  template_id: "collection.hard_suspend",
                  include_payment_link: True,
                  channels: [policy_types.Whatsapp],
                ),
              ],
              reason: "when_condition_matched",
            ),
          ]),
          policy_simulator.SimulationRow(day: 22, matches: [
            policy_simulator.SimulationMatch(
              stage_id: "hard_suspend",
              actions: [
                policy_types.SuspendService(reason: "overdue_collection"),
                policy_types.SendNotification(
                  template_id: "collection.hard_suspend",
                  include_payment_link: True,
                  channels: [policy_types.Whatsapp],
                ),
              ],
              reason: "when_condition_matched",
            ),
          ]),
        ]
    }
    Error(_) -> panic
  }
}

pub fn policy_simulator_respects_grace_days_test() {
  let policy = sample_policy(5)

  case policy_simulator.simulate_days(policy, sample_context(0), 5, 6) {
    Ok(rows) -> {
      assert rows
        == [
          policy_simulator.SimulationRow(day: 5, matches: []),
          policy_simulator.SimulationRow(day: 6, matches: [
            policy_simulator.SimulationMatch(
              stage_id: "soft_throttle",
              actions: [
                policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
                policy_types.SendNotification(
                  template_id: "collection.soft_throttle",
                  include_payment_link: True,
                  channels: [policy_types.Whatsapp, policy_types.Email],
                ),
              ],
              reason: "when_condition_matched",
            ),
          ]),
        ]
    }
    Error(_) -> panic
  }
}

pub fn policy_evaluator_deterministic_output_test() {
  let policy = sample_policy(0)
  let context = sample_context(12)

  let first = policy_evaluator.evaluate(policy, context)
  let second = policy_evaluator.evaluate(policy, context)

  assert first == second
}

fn sample_policy(grace_days: Int) -> policy_types.Policy {
  let soft_stage =
    policy_types.Stage(
      id: "soft_throttle",
      priority: 10,
      condition: days_between_condition(6, 20),
      actions: [
        policy_types.ApplyBandwidthProfile(profile_id: "bw_4mbps"),
        policy_types.SendNotification(
          template_id: "collection.soft_throttle",
          include_payment_link: True,
          channels: [policy_types.Whatsapp, policy_types.Email],
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
    grace_days: grace_days,
    timezone: "Asia/Jakarta",
    context: option.Some(policy_types.PolicyContextConfig(
      evaluation_time: option.Some("00:15"),
      payment_link_mode: option.Some(policy_types.SignedPaymentLink),
      payment_link_base_url: option.Some("https://pay.example.test"),
      payment_link_ttl_minutes: option.Some(60),
    )),
    stages: [hard_stage, soft_stage],
  )
}

fn sample_context(day: Int) -> policy_types.Context {
  policy_types.Context(
    days_past_due: day,
    invoice_status: "Overdue",
    operational_state: "normal",
    billing_plan: "postpaid",
    total_due_amount: 100_000,
    is_paid: False,
  )
}

fn days_between_condition(min: Int, max: Int) -> policy_types.Condition {
  policy_types.All([
    policy_types.Rule(
      field: policy_types.DaysPastDue,
      op: policy_types.Gte,
      value: policy_types.ScalarValue(policy_types.IntValue(min)),
      enabled: True,
    ),
    policy_types.Rule(
      field: policy_types.DaysPastDue,
      op: policy_types.Lte,
      value: policy_types.ScalarValue(policy_types.IntValue(max)),
      enabled: True,
    ),
  ])
}
