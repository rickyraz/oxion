import gleam/int
import gleam/list
import gleam/option
import gleam/string
import policy_types

pub type ValidationCode {
  EmptyConditionGroupCode
  InvalidOperatorForFieldCode
  MissingRequiredValueCode
  UnexpectedValueCode
  InvalidValueTypeCode
  InvalidBetweenRangeCode
  InvalidStagePriorityCode
  DuplicateStageIdCode
  MissingStagesCode
  MissingActionsCode
  InvalidPolicyNameCode
  InvalidPolicyDescriptionCode
  InvalidTimezoneCode
  InvalidGraceDaysCode
  InvalidStageIdCode
  InvalidNotificationTemplateCode
  InvalidActionConfigCode
  InvalidContextConfigCode
}

pub type ValidationError {
  ValidationError(code: ValidationCode, path: String, reason: String)
}

/// Validates a policy structure and semantics before it can be simulated or published.
pub fn validate_policy(
  policy: policy_types.Policy,
) -> Result(Nil, List(ValidationError)) {
  let policy_types.Policy(
    name: name,
    description: description,
    grace_days: grace_days,
    timezone: timezone,
    context: context,
    stages: stages,
  ) = policy

  let policy_errors =
    validate_policy_root(
      name,
      description,
      grace_days,
      timezone,
      context,
      stages,
    )
  let stage_errors = validate_stage_list(stages)
  let condition_errors = validate_stage_conditions(stages)
  let action_errors = validate_stage_actions(stages)
  let errors =
    list.append(
      policy_errors,
      list.append(stage_errors, list.append(condition_errors, action_errors)),
    )

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

// Why: schema-level fields such as timezone, context, and stage presence are
// publish gates, so they must be validated before deeper semantic checks run.
fn validate_policy_root(
  name: String,
  description: option.Option(String),
  grace_days: Int,
  timezone: String,
  context: option.Option(policy_types.PolicyContextConfig),
  stages: List(policy_types.Stage),
) -> List(ValidationError) {
  let name_errors = case
    string.length(name) >= 3 && string.length(name) <= 120
  {
    True -> []
    False -> [
      validation_error(
        InvalidPolicyNameCode,
        "name",
        "policy_name_out_of_range",
      ),
    ]
  }

  let description_errors = case description {
    option.None -> []
    option.Some(value) ->
      case string.length(value) <= 500 {
        True -> []
        False -> [
          validation_error(
            InvalidPolicyDescriptionCode,
            "description",
            "policy_description_out_of_range",
          ),
        ]
      }
  }

  let grace_errors = case grace_days >= 0 {
    True -> []
    False -> [
      validation_error(
        InvalidGraceDaysCode,
        "grace_days",
        "grace_days_must_be_non_negative",
      ),
    ]
  }

  let timezone_errors = case is_valid_timezone(timezone) {
    True -> []
    False -> [
      validation_error(
        InvalidTimezoneCode,
        "timezone",
        "timezone_must_match_iana_like_pattern",
      ),
    ]
  }

  let stage_errors = case stages {
    [] -> [
      validation_error(
        MissingStagesCode,
        "stages",
        "policy_must_define_at_least_one_stage",
      ),
    ]
    _ -> []
  }

  list.append(
    name_errors,
    list.append(
      description_errors,
      list.append(
        grace_errors,
        list.append(
          timezone_errors,
          list.append(stage_errors, validate_context(context)),
        ),
      ),
    ),
  )
}

// Why: policy context carries payment-link and schedule metadata from the
// schema, so rejecting malformed values here avoids silent drift later.
fn validate_context(
  context: option.Option(policy_types.PolicyContextConfig),
) -> List(ValidationError) {
  case context {
    option.None -> []
    option.Some(config) -> {
      let policy_types.PolicyContextConfig(
        evaluation_time: evaluation_time,
        payment_link_mode: _payment_link_mode,
        payment_link_base_url: payment_link_base_url,
        payment_link_ttl_minutes: payment_link_ttl_minutes,
      ) = config

      let time_errors = case evaluation_time {
        option.None -> []
        option.Some(value) ->
          case is_valid_time(value) {
            True -> []
            False -> [
              validation_error(
                InvalidContextConfigCode,
                "context.evaluation_time",
                "evaluation_time_must_be_hh_mm",
              ),
            ]
          }
      }

      let url_errors = case payment_link_base_url {
        option.None -> []
        option.Some(value) ->
          case is_probably_uri(value) {
            True -> []
            False -> [
              validation_error(
                InvalidContextConfigCode,
                "context.payment_link_base_url",
                "payment_link_base_url_must_be_uri_like",
              ),
            ]
          }
      }

      let ttl_errors = case payment_link_ttl_minutes {
        option.None -> []
        option.Some(value) ->
          case value >= 1 && value <= 10_080 {
            True -> []
            False -> [
              validation_error(
                InvalidContextConfigCode,
                "context.payment_link_ttl_minutes",
                "payment_link_ttl_minutes_out_of_range",
              ),
            ]
          }
      }

      list.append(time_errors, list.append(url_errors, ttl_errors))
    }
  }
}

// Validates stage-level constraints such as unique IDs and positive priority.
fn validate_stage_list(
  stages: List(policy_types.Stage),
) -> List(ValidationError) {
  validate_stage_list_loop(stages, [], [], 0)
}

// Why: stage identity and ordering are part of the deterministic contract, so
// bad IDs or priorities need a stable indexed path in the error output.
fn validate_stage_list_loop(
  remaining: List(policy_types.Stage),
  seen_ids: List(String),
  errors: List(ValidationError),
  idx: Int,
) -> List(ValidationError) {
  case remaining {
    [] -> errors
    [
      policy_types.Stage(
        id: id,
        priority: priority,
        condition: _condition,
        actions: _actions,
        stop_on_match: _stop_on_match,
        notification_template: notification_template,
        enabled: _enabled,
      ),
      ..rest
    ] -> {
      let path = stage_path(idx)

      let duplicate_error = case list.contains(seen_ids, id) {
        True -> [
          validation_error(
            DuplicateStageIdCode,
            path <> ".id",
            "stage_id_must_be_unique",
          ),
        ]
        False -> []
      }

      let id_error = case is_valid_stage_id(id) {
        True -> []
        False -> [
          validation_error(
            InvalidStageIdCode,
            path <> ".id",
            "stage_id_must_match_schema_pattern",
          ),
        ]
      }

      let priority_error = case priority >= 1 && priority <= 10_000 {
        True -> []
        False -> [
          validation_error(
            InvalidStagePriorityCode,
            path <> ".priority",
            "stage_priority_out_of_range",
          ),
        ]
      }

      let template_error = case notification_template {
        option.None -> []
        option.Some(template) ->
          case string.length(template) >= 1 && string.length(template) <= 120 {
            True -> []
            False -> [
              validation_error(
                InvalidNotificationTemplateCode,
                path <> ".notification_template",
                "notification_template_out_of_range",
              ),
            ]
          }
      }

      let next_errors =
        list.append(
          errors,
          list.append(
            duplicate_error,
            list.append(id_error, list.append(priority_error, template_error)),
          ),
        )

      validate_stage_list_loop(rest, [id, ..seen_ids], next_errors, idx + 1)
    }
  }
}

// Validates all `when` conditions for each stage.
fn validate_stage_conditions(
  stages: List(policy_types.Stage),
) -> List(ValidationError) {
  validate_stage_conditions_loop(stages, [], 0)
}

// Walks stages and validates each condition tree path for clear error reporting.
fn validate_stage_conditions_loop(
  remaining: List(policy_types.Stage),
  errors: List(ValidationError),
  idx: Int,
) -> List(ValidationError) {
  case remaining {
    [] -> errors
    [
      policy_types.Stage(
        id: _id,
        priority: _priority,
        condition: condition,
        actions: _actions,
        stop_on_match: _stop_on_match,
        notification_template: _notification_template,
        enabled: _enabled,
      ),
      ..rest
    ] -> {
      let condition_errors =
        validate_condition(condition, stage_path(idx) <> ".when")
      validate_stage_conditions_loop(
        rest,
        list.append(errors, condition_errors),
        idx + 1,
      )
    }
  }
}

// Validates all actions and payload-bearing metadata for each stage.
fn validate_stage_actions(
  stages: List(policy_types.Stage),
) -> List(ValidationError) {
  validate_stage_actions_loop(stages, [], 0)
}

fn validate_stage_actions_loop(
  remaining: List(policy_types.Stage),
  errors: List(ValidationError),
  idx: Int,
) -> List(ValidationError) {
  case remaining {
    [] -> errors
    [
      policy_types.Stage(
        id: _id,
        priority: _priority,
        condition: _condition,
        actions: actions,
        stop_on_match: _stop_on_match,
        notification_template: _notification_template,
        enabled: _enabled,
      ),
      ..rest
    ] -> {
      let path = stage_path(idx) <> ".actions"
      let action_errors = case actions {
        [] -> [
          validation_error(
            MissingActionsCode,
            path,
            "stage_must_define_at_least_one_action",
          ),
        ]
        _ -> validate_actions(actions, path, 0, [])
      }

      validate_stage_actions_loop(
        rest,
        list.append(errors, action_errors),
        idx + 1,
      )
    }
  }
}

// Validates a single condition node (`all`, `any`, or `rule`).
fn validate_condition(
  condition: policy_types.Condition,
  path: String,
) -> List(ValidationError) {
  case condition {
    policy_types.All(conditions) ->
      case conditions {
        [] -> [
          validation_error(
            EmptyConditionGroupCode,
            path,
            "all_requires_at_least_one_condition",
          ),
        ]
        _ -> validate_nested_conditions(conditions, path)
      }

    policy_types.Any(conditions) ->
      case conditions {
        [] -> [
          validation_error(
            EmptyConditionGroupCode,
            path,
            "any_requires_at_least_one_condition",
          ),
        ]
        _ -> validate_nested_conditions(conditions, path)
      }

    policy_types.Rule(field, op, value, _) ->
      validate_rule(field, op, value, path)
  }
}

// Validates nested condition groups and forwards path context.
fn validate_nested_conditions(
  conditions: List(policy_types.Condition),
  path: String,
) -> List(ValidationError) {
  validate_nested_conditions_loop(conditions, path, 0, [])
}

// Iterates nested conditions while preserving indexed paths.
fn validate_nested_conditions_loop(
  remaining: List(policy_types.Condition),
  path: String,
  idx: Int,
  errors: List(ValidationError),
) -> List(ValidationError) {
  case remaining {
    [] -> errors
    [condition, ..rest] -> {
      let next =
        validate_condition(
          condition,
          path <> ".conditions[" <> int.to_string(idx) <> "]",
        )

      validate_nested_conditions_loop(
        rest,
        path,
        idx + 1,
        list.append(errors, next),
      )
    }
  }
}

// Why: evaluator compatibility depends on operator/value discipline, so invalid
// pairings must be rejected before runtime instead of being treated as `False`.
fn validate_rule(
  field: policy_types.Field,
  op: policy_types.Operator,
  value: policy_types.Value,
  path: String,
) -> List(ValidationError) {
  case op {
    policy_types.IsTrue | policy_types.IsFalse ->
      case value {
        policy_types.NoValue -> validate_operator_compat(field, op, path)
        _ -> [
          validation_error(
            UnexpectedValueCode,
            path <> ".value",
            "boolean_shortcut_operator_does_not_accept_value",
          ),
        ]
      }

    policy_types.Between ->
      case value {
        policy_types.BetweenValue(min:, max:) ->
          case min <= max {
            True -> validate_operator_compat(field, op, path)
            False -> [
              validation_error(
                InvalidBetweenRangeCode,
                path <> ".value",
                "between_min_must_be_lte_max",
              ),
            ]
          }
        policy_types.NoValue -> [
          validation_error(
            MissingRequiredValueCode,
            path <> ".value",
            "between_requires_value",
          ),
        ]
        _ -> [
          validation_error(
            InvalidValueTypeCode,
            path <> ".value",
            "between_requires_range_object",
          ),
        ]
      }

    policy_types.In | policy_types.NotIn ->
      case value {
        policy_types.ListValue(items) ->
          case list_value_matches_field(items, field) {
            True -> validate_operator_compat(field, op, path)
            False -> [
              validation_error(
                InvalidValueTypeCode,
                path <> ".value",
                "list_value_does_not_match_field_type",
              ),
            ]
          }
        policy_types.NoValue -> [
          validation_error(
            MissingRequiredValueCode,
            path <> ".value",
            "membership_operator_requires_value",
          ),
        ]
        _ -> [
          validation_error(
            InvalidValueTypeCode,
            path <> ".value",
            "membership_operator_requires_list_value",
          ),
        ]
      }

    _ ->
      case value {
        policy_types.ScalarValue(scalar) ->
          case scalar_matches_field(scalar, field) {
            True -> validate_operator_compat(field, op, path)
            False -> [
              validation_error(
                InvalidValueTypeCode,
                path <> ".value",
                "scalar_value_does_not_match_field_type",
              ),
            ]
          }
        policy_types.NoValue -> [
          validation_error(
            MissingRequiredValueCode,
            path <> ".value",
            "scalar_operator_requires_value",
          ),
        ]
        _ -> [
          validation_error(
            InvalidValueTypeCode,
            path <> ".value",
            "scalar_operator_requires_scalar_value",
          ),
        ]
      }
  }
}

fn validate_actions(
  remaining: List(policy_types.Action),
  path: String,
  idx: Int,
  errors: List(ValidationError),
) -> List(ValidationError) {
  case remaining {
    [] -> errors
    [action, ..rest] -> {
      let next_path = path <> "[" <> int.to_string(idx) <> "]"
      let next_errors = list.append(errors, validate_action(action, next_path))
      validate_actions(rest, path, idx + 1, next_errors)
    }
  }
}

fn validate_action(
  action: policy_types.Action,
  path: String,
) -> List(ValidationError) {
  case action {
    policy_types.ApplyBandwidthProfile(profile_id) ->
      validate_string_range(
        profile_id,
        path <> ".profile_id",
        1,
        120,
        "profile_id_out_of_range",
      )

    policy_types.SuspendService(reason) ->
      validate_string_range(
        reason,
        path <> ".reason",
        3,
        200,
        "suspend_reason_out_of_range",
      )

    policy_types.RestoreService -> []

    policy_types.SendNotification(template_id, _, channels) -> {
      let template_errors =
        validate_string_range(
          template_id,
          path <> ".template_id",
          1,
          120,
          "template_id_out_of_range",
        )

      let channel_errors = case channels_are_unique(channels, []) {
        True -> []
        False -> [
          validation_error(
            InvalidActionConfigCode,
            path <> ".channels",
            "notification_channels_must_be_unique",
          ),
        ]
      }

      list.append(template_errors, channel_errors)
    }

    policy_types.EmitEvent(topic, payload) -> {
      let topic_errors =
        validate_string_range(
          topic,
          path <> ".topic",
          3,
          200,
          "event_topic_out_of_range",
        )

      let payload_errors = validate_object_payload(payload, path <> ".payload")
      list.append(topic_errors, payload_errors)
    }

    policy_types.SetOperationalState(state) ->
      case is_valid_operational_state(state) {
        True -> []
        False -> [
          validation_error(
            InvalidActionConfigCode,
            path <> ".state",
            "operational_state_must_match_schema_enum",
          ),
        ]
      }

    policy_types.RunPluginHook(plugin_id, hook, payload) -> {
      let plugin_errors = case is_valid_plugin_id(plugin_id) {
        True -> []
        False -> [
          validation_error(
            InvalidActionConfigCode,
            path <> ".plugin_id",
            "plugin_id_must_match_schema_pattern",
          ),
        ]
      }

      let hook_errors =
        validate_string_range(
          hook,
          path <> ".hook",
          1,
          80,
          "plugin_hook_out_of_range",
        )

      let payload_errors = validate_object_payload(payload, path <> ".payload")
      list.append(plugin_errors, list.append(hook_errors, payload_errors))
    }
  }
}

// Ensures scalar value type matches the selected field domain.
fn scalar_matches_field(
  scalar: policy_types.Scalar,
  field: policy_types.Field,
) -> Bool {
  case field {
    policy_types.DaysPastDue | policy_types.TotalDueAmount ->
      case scalar {
        policy_types.IntValue(_) -> True
        _ -> False
      }

    policy_types.InvoiceStatus
    | policy_types.OperationalState
    | policy_types.BillingPlan ->
      case scalar {
        policy_types.StringValue(_) -> True
        _ -> False
      }

    policy_types.IsPaid ->
      case scalar {
        policy_types.BoolValue(_) -> True
        _ -> False
      }
  }
}

// Ensures all list items match the selected field domain.
fn list_value_matches_field(
  items: List(policy_types.Scalar),
  field: policy_types.Field,
) -> Bool {
  case items {
    [] -> True
    [item, ..rest] ->
      case scalar_matches_field(item, field) {
        True -> list_value_matches_field(rest, field)
        False -> False
      }
  }
}

// Wraps operator compatibility checks into normalized validation errors.
fn validate_operator_compat(
  field: policy_types.Field,
  op: policy_types.Operator,
  path: String,
) -> List(ValidationError) {
  case is_compatible(field, op) {
    True -> []
    False -> [
      validation_error(
        InvalidOperatorForFieldCode,
        path <> ".op",
        "operator_not_allowed_for_field",
      ),
    ]
  }
}

// Returns `True` if an operator is allowed for a field.
fn is_compatible(field: policy_types.Field, op: policy_types.Operator) -> Bool {
  case field {
    policy_types.DaysPastDue | policy_types.TotalDueAmount ->
      is_numeric_operator(op)

    policy_types.InvoiceStatus
    | policy_types.OperationalState
    | policy_types.BillingPlan -> is_string_operator(op)

    policy_types.IsPaid ->
      case op {
        policy_types.Eq
        | policy_types.Ne
        | policy_types.IsTrue
        | policy_types.IsFalse -> True
        _ -> False
      }
  }
}

// Defines the operator set for numeric fields.
fn is_numeric_operator(op: policy_types.Operator) -> Bool {
  case op {
    policy_types.Eq
    | policy_types.Ne
    | policy_types.Gt
    | policy_types.Gte
    | policy_types.Lt
    | policy_types.Lte
    | policy_types.In
    | policy_types.NotIn
    | policy_types.Between -> True
    _ -> False
  }
}

// Defines the operator set for string fields.
fn is_string_operator(op: policy_types.Operator) -> Bool {
  case op {
    policy_types.Eq | policy_types.Ne | policy_types.In | policy_types.NotIn ->
      True
    _ -> False
  }
}

fn validate_string_range(
  value: String,
  path: String,
  min_length: Int,
  max_length: Int,
  reason: String,
) -> List(ValidationError) {
  let length = string.length(value)
  case length >= min_length && length <= max_length {
    True -> []
    False -> [validation_error(InvalidActionConfigCode, path, reason)]
  }
}

fn validate_object_payload(
  payload: option.Option(policy_types.JsonValue),
  path: String,
) -> List(ValidationError) {
  case payload {
    option.None -> []
    option.Some(policy_types.JsonObject(_)) -> []
    option.Some(_) -> [
      validation_error(
        InvalidActionConfigCode,
        path,
        "payload_must_be_json_object",
      ),
    ]
  }
}

fn channels_are_unique(
  remaining: List(policy_types.NotificationChannel),
  seen: List(policy_types.NotificationChannel),
) -> Bool {
  case remaining {
    [] -> True
    [channel, ..rest] ->
      case list.contains(seen, channel) {
        True -> False
        False -> channels_are_unique(rest, [channel, ..seen])
      }
  }
}

fn stage_path(idx: Int) -> String {
  "stages[" <> int.to_string(idx) <> "]"
}

fn validation_error(
  code: ValidationCode,
  path: String,
  reason: String,
) -> ValidationError {
  ValidationError(code:, path:, reason:)
}

fn is_valid_timezone(timezone: String) -> Bool {
  case string.split(timezone, on: "/") {
    [first, second] ->
      is_valid_timezone_segment(first) && is_valid_timezone_segment(second)
    [first, second, third] ->
      is_valid_timezone_segment(first)
      && is_valid_timezone_segment(second)
      && is_valid_timezone_segment(third)
    _ -> False
  }
}

fn is_valid_stage_id(stage_id: String) -> Bool {
  let graphemes = string.to_graphemes(stage_id)
  case graphemes {
    [] -> False
    [first, ..rest] -> {
      let length = list.length(graphemes)
      length >= 3
      && length <= 64
      && is_lowercase_letter(first)
      && stage_id_tail_is_valid(rest)
    }
  }
}

fn is_valid_plugin_id(plugin_id: String) -> Bool {
  let length = string.length(plugin_id)
  length >= 5
  && length <= 120
  && plugin_id_segments_are_valid(string.split(plugin_id, on: "."), True)
}

fn is_valid_operational_state(state: String) -> Bool {
  case state {
    "normal" | "throttled_due_overdue" | "suspended_due_overdue" -> True
    _ -> False
  }
}

fn is_probably_uri(value: String) -> Bool {
  case string.split(value, on: "://") {
    [scheme, rest] ->
      is_valid_uri_scheme(string.to_graphemes(scheme))
      && string.length(rest) > 0
    _ -> False
  }
}

fn is_valid_time(value: String) -> Bool {
  case string.split(value, on: ":") {
    [hour, minute] ->
      case int.parse(hour), int.parse(minute) {
        Ok(parsed_hour), Ok(parsed_minute) ->
          string.length(hour) == 2
          && string.length(minute) == 2
          && parsed_hour >= 0
          && parsed_hour <= 23
          && parsed_minute >= 0
          && parsed_minute <= 59
        _, _ -> False
      }
    _ -> False
  }
}

fn is_valid_timezone_segment(value: String) -> Bool {
  case string.to_graphemes(value) {
    [] -> False
    graphemes -> all_timezone_segment_chars(graphemes)
  }
}

fn all_timezone_segment_chars(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> True
    [grapheme, ..rest] ->
      case is_alpha_or_underscore(grapheme) {
        True -> all_timezone_segment_chars(rest)
        False -> False
      }
  }
}

fn stage_id_tail_is_valid(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> True
    [grapheme, ..rest] ->
      case
        is_lowercase_letter(grapheme)
        || is_digit(grapheme)
        || grapheme == "_"
        || grapheme == "-"
      {
        True -> stage_id_tail_is_valid(rest)
        False -> False
      }
  }
}

fn plugin_id_segments_are_valid(segments: List(String), is_first: Bool) -> Bool {
  case segments {
    [] -> False
    [segment] ->
      case is_first {
        True -> False
        False -> plugin_segment_is_valid(segment, False)
      }
    [segment, ..rest] ->
      case plugin_segment_is_valid(segment, is_first) {
        True -> plugin_id_segments_are_valid(rest, False)
        False -> False
      }
  }
}

fn plugin_segment_is_valid(segment: String, is_first: Bool) -> Bool {
  case string.to_graphemes(segment) {
    [] -> False
    graphemes ->
      case is_first {
        True -> all_plugin_head_chars(graphemes)
        False -> all_plugin_tail_chars(graphemes)
      }
  }
}

fn all_plugin_head_chars(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> True
    [grapheme, ..rest] ->
      case is_lowercase_letter(grapheme) || is_digit(grapheme) {
        True -> all_plugin_head_chars(rest)
        False -> False
      }
  }
}

fn all_plugin_tail_chars(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> True
    [grapheme, ..rest] ->
      case
        is_lowercase_letter(grapheme) || is_digit(grapheme) || grapheme == "-"
      {
        True -> all_plugin_tail_chars(rest)
        False -> False
      }
  }
}

fn is_valid_uri_scheme(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> False
    [first, ..rest] -> is_letter(first) && uri_scheme_tail_is_valid(rest)
  }
}

fn uri_scheme_tail_is_valid(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> True
    [grapheme, ..rest] ->
      case
        is_letter(grapheme)
        || is_digit(grapheme)
        || grapheme == "+"
        || grapheme == "."
        || grapheme == "-"
      {
        True -> uri_scheme_tail_is_valid(rest)
        False -> False
      }
  }
}

fn is_alpha_or_underscore(grapheme: String) -> Bool {
  is_letter(grapheme) || grapheme == "_"
}

fn is_letter(grapheme: String) -> Bool {
  is_lowercase_letter(grapheme) || is_uppercase_letter(grapheme)
}

fn is_lowercase_letter(grapheme: String) -> Bool {
  case grapheme {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    _ -> False
  }
}

fn is_uppercase_letter(grapheme: String) -> Bool {
  case grapheme {
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    _ -> False
  }
}

fn is_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
