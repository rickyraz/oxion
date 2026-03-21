import gleam/int
import gleam/list
import gleam/order
import gleam/string
import oxion/policy/types as policy_types

pub type EvaluationError {
  EvaluationError(code: String, stage_id: String, path: String, reason: String)
}

pub type StageMatch {
  StageMatch(stage_id: String, actions: List(policy_types.Action))
}

pub type EvaluationResult {
  EvaluationResult(matches: List(StageMatch))
}

/// Evaluates a policy against runtime context and returns matched stages deterministically.
pub fn evaluate(
  policy: policy_types.Policy,
  context: policy_types.Context,
) -> Result(EvaluationResult, EvaluationError) {
  let policy_types.Policy(
    name: _name,
    description: _description,
    grace_days: _grace_days,
    timezone: _timezone,
    context: _policy_context,
    stages: stages,
  ) = policy

  let ordered = order_stages(index_stages(stages, 0, []))
  case evaluate_stages(ordered, context, []) {
    Ok(matches) -> Ok(EvaluationResult(matches: matches))
    Error(error) -> Error(error)
  }
}

// Why: sorting must stay deterministic without losing the original stage index
// that is needed for spec-compliant error paths.
fn index_stages(
  remaining: List(policy_types.Stage),
  idx: Int,
  acc: List(#(Int, policy_types.Stage)),
) -> List(#(Int, policy_types.Stage)) {
  case remaining {
    [] -> list.reverse(acc)
    [stage, ..rest] -> index_stages(rest, idx + 1, [#(idx, stage), ..acc])
  }
}

// Orders stages by priority and deterministic ID tie-break.
fn order_stages(
  stages: List(#(Int, policy_types.Stage)),
) -> List(#(Int, policy_types.Stage)) {
  insert_sort(stages, [])
}

// Runs insertion sort to keep ordering logic explicit.
fn insert_sort(
  remaining: List(#(Int, policy_types.Stage)),
  sorted: List(#(Int, policy_types.Stage)),
) -> List(#(Int, policy_types.Stage)) {
  case remaining {
    [] -> sorted
    [stage, ..rest] -> insert_sort(rest, insert_stage(stage, sorted))
  }
}

// Inserts one stage into a sorted list.
fn insert_stage(
  stage: #(Int, policy_types.Stage),
  sorted: List(#(Int, policy_types.Stage)),
) -> List(#(Int, policy_types.Stage)) {
  case sorted {
    [] -> [stage]
    [head, ..tail] ->
      case stage_before(stage, head) {
        True -> [stage, head, ..tail]
        False -> [head, ..insert_stage(stage, tail)]
      }
  }
}

// Compares two stages using priority first, then lexicographic ID.
fn stage_before(
  a: #(Int, policy_types.Stage),
  b: #(Int, policy_types.Stage),
) -> Bool {
  let #(
    _a_index,
    policy_types.Stage(
      id: a_id,
      priority: a_priority,
      condition: _a_condition,
      actions: _a_actions,
      stop_on_match: _a_stop,
      notification_template: _a_template,
      enabled: _a_enabled,
    ),
  ) = a
  let #(
    _b_index,
    policy_types.Stage(
      id: b_id,
      priority: b_priority,
      condition: _b_condition,
      actions: _b_actions,
      stop_on_match: _b_stop,
      notification_template: _b_template,
      enabled: _b_enabled,
    ),
  ) = b

  case a_priority < b_priority {
    True -> True
    False ->
      case a_priority > b_priority {
        True -> False
        False ->
          case string.compare(a_id, b_id) {
            order.Lt -> True
            _ -> False
          }
      }
  }
}

// Evaluates all stages and applies stop-on-match semantics.
fn evaluate_stages(
  remaining: List(#(Int, policy_types.Stage)),
  context: policy_types.Context,
  acc: List(StageMatch),
) -> Result(List(StageMatch), EvaluationError) {
  case remaining {
    [] -> Ok(acc)
    [
      #(
        stage_index,
        policy_types.Stage(
          id: id,
          priority: _priority,
          condition: condition,
          actions: actions,
          stop_on_match: stop_on_match,
          notification_template: _notification_template,
          enabled: enabled,
        ),
      ),
      ..rest
    ] -> {
      case enabled {
        False -> evaluate_stages(rest, context, acc)
        True -> {
          let path = stage_path(stage_index)
          case evaluate_condition(condition, context, id, path <> ".when") {
            Ok(True) -> {
              let next_acc =
                list.append(acc, [StageMatch(stage_id: id, actions: actions)])
              case stop_on_match {
                True -> Ok(next_acc)
                False -> evaluate_stages(rest, context, next_acc)
              }
            }
            Ok(False) -> evaluate_stages(rest, context, acc)
            Error(error) -> Error(error)
          }
        }
      }
    }
  }
}

// Evaluates one condition node (`all`, `any`, or `rule`).
fn evaluate_condition(
  condition: policy_types.Condition,
  context: policy_types.Context,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case condition {
    policy_types.All(conditions) ->
      eval_all(conditions, context, stage_id, path, 0)
    policy_types.Any(conditions) ->
      eval_any(conditions, context, stage_id, path, 0)
    policy_types.Rule(field, op, value, enabled) ->
      case enabled {
        False -> Ok(False)
        True -> eval_rule(field, op, value, context, stage_id, path)
      }
  }
}

// Returns true only if every child condition matches.
fn eval_all(
  conditions: List(policy_types.Condition),
  context: policy_types.Context,
  stage_id: String,
  path: String,
  idx: Int,
) -> Result(Bool, EvaluationError) {
  case conditions {
    [] -> Error(evaluation_error(stage_id, path, "empty_condition_group"))
    [condition, ..rest] -> {
      let child_path = path <> ".conditions[" <> int.to_string(idx) <> "]"
      case evaluate_condition(condition, context, stage_id, child_path) {
        Ok(True) ->
          case rest {
            [] -> Ok(True)
            _ -> eval_all(rest, context, stage_id, path, idx + 1)
          }
        Ok(False) -> Ok(False)
        Error(error) -> Error(error)
      }
    }
  }
}

// Returns true if any child condition matches.
fn eval_any(
  conditions: List(policy_types.Condition),
  context: policy_types.Context,
  stage_id: String,
  path: String,
  idx: Int,
) -> Result(Bool, EvaluationError) {
  case conditions {
    [] -> Error(evaluation_error(stage_id, path, "empty_condition_group"))
    [condition, ..rest] -> {
      let child_path = path <> ".conditions[" <> int.to_string(idx) <> "]"
      case evaluate_condition(condition, context, stage_id, child_path) {
        Ok(True) -> Ok(True)
        Ok(False) ->
          case rest {
            [] -> Ok(False)
            _ -> eval_any(rest, context, stage_id, path, idx + 1)
          }
        Error(error) -> Error(error)
      }
    }
  }
}

// Routes rule evaluation to the correct field-domain evaluator.
fn eval_rule(
  field: policy_types.Field,
  op: policy_types.Operator,
  value: policy_types.Value,
  context: policy_types.Context,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case field {
    policy_types.DaysPastDue ->
      eval_int_rule(context.days_past_due, op, value, stage_id, path)

    policy_types.TotalDueAmount ->
      eval_int_rule(context.total_due_amount, op, value, stage_id, path)

    policy_types.InvoiceStatus ->
      eval_string_rule(context.invoice_status, op, value, stage_id, path)

    policy_types.OperationalState ->
      eval_string_rule(context.operational_state, op, value, stage_id, path)

    policy_types.BillingPlan ->
      eval_string_rule(context.billing_plan, op, value, stage_id, path)

    policy_types.IsPaid ->
      eval_bool_rule(context.is_paid, op, value, stage_id, path)
  }
}

// Why: invalid operator/value combinations are contract errors, not ordinary
// non-matches, so numeric evaluation returns `Error` instead of hiding them.
fn eval_int_rule(
  actual: Int,
  op: policy_types.Operator,
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case op {
    policy_types.Eq ->
      compare_int_rule(value, stage_id, path, fn(expected) {
        actual == expected
      })
    policy_types.Ne ->
      compare_int_rule(value, stage_id, path, fn(expected) {
        actual != expected
      })
    policy_types.Gt ->
      compare_int_rule(value, stage_id, path, fn(expected) { actual > expected })
    policy_types.Gte ->
      compare_int_rule(value, stage_id, path, fn(expected) {
        actual >= expected
      })
    policy_types.Lt ->
      compare_int_rule(value, stage_id, path, fn(expected) { actual < expected })
    policy_types.Lte ->
      compare_int_rule(value, stage_id, path, fn(expected) {
        actual <= expected
      })
    policy_types.In -> int_membership_rule(actual, value, stage_id, path, False)
    policy_types.NotIn ->
      int_membership_rule(actual, value, stage_id, path, True)
    policy_types.Between -> between_rule(actual, value, stage_id, path)
    policy_types.IsTrue | policy_types.IsFalse ->
      Error(evaluation_error(
        stage_id,
        path <> ".op",
        "operator_not_allowed_for_numeric_field",
      ))
  }
}

// Evaluates string operators for equality and membership.
fn eval_string_rule(
  actual: String,
  op: policy_types.Operator,
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case op {
    policy_types.Eq ->
      compare_string_rule(value, stage_id, path, fn(expected) {
        actual == expected
      })
    policy_types.Ne ->
      compare_string_rule(value, stage_id, path, fn(expected) {
        actual != expected
      })
    policy_types.In ->
      string_membership_rule(actual, value, stage_id, path, False)
    policy_types.NotIn ->
      string_membership_rule(actual, value, stage_id, path, True)
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".op",
        "operator_not_allowed_for_string_field",
      ))
  }
}

// Evaluates boolean operators and boolean shortcut operators.
fn eval_bool_rule(
  actual: Bool,
  op: policy_types.Operator,
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case op {
    policy_types.Eq ->
      compare_bool_rule(value, stage_id, path, fn(expected) {
        actual == expected
      })
    policy_types.Ne ->
      compare_bool_rule(value, stage_id, path, fn(expected) {
        actual != expected
      })
    policy_types.IsTrue ->
      bool_shortcut_rule(actual, value, stage_id, path, False)
    policy_types.IsFalse ->
      bool_shortcut_rule(actual, value, stage_id, path, True)
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".op",
        "operator_not_allowed_for_boolean_field",
      ))
  }
}

fn compare_int_rule(
  value: policy_types.Value,
  stage_id: String,
  path: String,
  compare: fn(Int) -> Bool,
) -> Result(Bool, EvaluationError) {
  case expect_int_scalar(value, stage_id, path) {
    Ok(expected) -> Ok(compare(expected))
    Error(error) -> Error(error)
  }
}

fn int_membership_rule(
  actual: Int,
  value: policy_types.Value,
  stage_id: String,
  path: String,
  negate: Bool,
) -> Result(Bool, EvaluationError) {
  case expect_int_list(value, stage_id, path) {
    Ok(items) ->
      case negate {
        True -> Ok(int_list_contains(actual, items) == False)
        False -> Ok(int_list_contains(actual, items))
      }
    Error(error) -> Error(error)
  }
}

fn between_rule(
  actual: Int,
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case expect_between_value(value, stage_id, path) {
    Ok(#(min, max)) -> Ok(actual >= min && actual <= max)
    Error(error) -> Error(error)
  }
}

fn compare_string_rule(
  value: policy_types.Value,
  stage_id: String,
  path: String,
  compare: fn(String) -> Bool,
) -> Result(Bool, EvaluationError) {
  case expect_string_scalar(value, stage_id, path) {
    Ok(expected) -> Ok(compare(expected))
    Error(error) -> Error(error)
  }
}

fn string_membership_rule(
  actual: String,
  value: policy_types.Value,
  stage_id: String,
  path: String,
  negate: Bool,
) -> Result(Bool, EvaluationError) {
  case expect_string_list(value, stage_id, path) {
    Ok(items) ->
      case negate {
        True -> Ok(string_list_contains(actual, items) == False)
        False -> Ok(string_list_contains(actual, items))
      }
    Error(error) -> Error(error)
  }
}

fn compare_bool_rule(
  value: policy_types.Value,
  stage_id: String,
  path: String,
  compare: fn(Bool) -> Bool,
) -> Result(Bool, EvaluationError) {
  case expect_bool_scalar(value, stage_id, path) {
    Ok(expected) -> Ok(compare(expected))
    Error(error) -> Error(error)
  }
}

fn bool_shortcut_rule(
  actual: Bool,
  value: policy_types.Value,
  stage_id: String,
  path: String,
  negate: Bool,
) -> Result(Bool, EvaluationError) {
  case expect_no_value(value, stage_id, path) {
    Ok(_) ->
      case negate {
        True -> Ok(!actual)
        False -> Ok(actual)
      }
    Error(error) -> Error(error)
  }
}

fn expect_int_scalar(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Int, EvaluationError) {
  case value {
    policy_types.ScalarValue(policy_types.IntValue(expected)) -> Ok(expected)
    policy_types.NoValue ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "scalar_operator_requires_value",
      ))
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "numeric_field_requires_int_value",
      ))
  }
}

fn expect_string_scalar(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(String, EvaluationError) {
  case value {
    policy_types.ScalarValue(policy_types.StringValue(expected)) -> Ok(expected)
    policy_types.NoValue ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "scalar_operator_requires_value",
      ))
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "string_field_requires_string_value",
      ))
  }
}

fn expect_bool_scalar(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Bool, EvaluationError) {
  case value {
    policy_types.ScalarValue(policy_types.BoolValue(expected)) -> Ok(expected)
    policy_types.NoValue ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "scalar_operator_requires_value",
      ))
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "boolean_field_requires_bool_value",
      ))
  }
}

fn expect_int_list(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(List(Int), EvaluationError) {
  case value {
    policy_types.ListValue(items) -> collect_int_list(items, stage_id, path, [])
    policy_types.NoValue ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "membership_operator_requires_value",
      ))
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "numeric_field_requires_int_list",
      ))
  }
}

fn collect_int_list(
  remaining: List(policy_types.Scalar),
  stage_id: String,
  path: String,
  acc: List(Int),
) -> Result(List(Int), EvaluationError) {
  case remaining {
    [] -> Ok(list.reverse(acc))
    [policy_types.IntValue(value), ..rest] ->
      collect_int_list(rest, stage_id, path, [value, ..acc])
    [_other, ..] ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "numeric_field_requires_int_list",
      ))
  }
}

fn expect_string_list(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(List(String), EvaluationError) {
  case value {
    policy_types.ListValue(items) ->
      collect_string_list(items, stage_id, path, [])
    policy_types.NoValue ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "membership_operator_requires_value",
      ))
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "string_field_requires_string_list",
      ))
  }
}

fn collect_string_list(
  remaining: List(policy_types.Scalar),
  stage_id: String,
  path: String,
  acc: List(String),
) -> Result(List(String), EvaluationError) {
  case remaining {
    [] -> Ok(list.reverse(acc))
    [policy_types.StringValue(value), ..rest] ->
      collect_string_list(rest, stage_id, path, [value, ..acc])
    [_other, ..] ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "string_field_requires_string_list",
      ))
  }
}

fn expect_between_value(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(#(Int, Int), EvaluationError) {
  case value {
    policy_types.BetweenValue(min:, max:) ->
      case min <= max {
        True -> Ok(#(min, max))
        False ->
          Error(evaluation_error(
            stage_id,
            path <> ".value",
            "between_min_must_be_lte_max",
          ))
      }
    policy_types.NoValue ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "between_requires_value",
      ))
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "between_requires_range_object",
      ))
  }
}

fn expect_no_value(
  value: policy_types.Value,
  stage_id: String,
  path: String,
) -> Result(Nil, EvaluationError) {
  case value {
    policy_types.NoValue -> Ok(Nil)
    _ ->
      Error(evaluation_error(
        stage_id,
        path <> ".value",
        "boolean_shortcut_operator_does_not_accept_value",
      ))
  }
}

fn int_list_contains(actual: Int, items: List(Int)) -> Bool {
  case items {
    [] -> False
    [value, ..rest] ->
      case actual == value {
        True -> True
        False -> int_list_contains(actual, rest)
      }
  }
}

fn string_list_contains(actual: String, items: List(String)) -> Bool {
  case items {
    [] -> False
    [value, ..rest] ->
      case actual == value {
        True -> True
        False -> string_list_contains(actual, rest)
      }
  }
}

fn stage_path(idx: Int) -> String {
  "stages[" <> int.to_string(idx) <> "]"
}

fn evaluation_error(
  stage_id: String,
  path: String,
  reason: String,
) -> EvaluationError {
  EvaluationError(
    code: "INVALID_WHEN_CONDITION",
    stage_id: stage_id,
    path: path,
    reason: reason,
  )
}
