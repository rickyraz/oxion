import gleam/list
import policy_evaluator
import policy_types

pub type SimulationMatch {
  SimulationMatch(
    stage_id: String,
    actions: List(policy_types.Action),
    reason: String,
  )
}

pub type SimulationRow {
  SimulationRow(day: Int, matches: List(SimulationMatch))
}

pub type SimulationError {
  InvalidRange
  EvaluationFailed(policy_evaluator.EvaluationError)
}

/// Simulates policy matches for a day range and returns detailed stage outcomes.
pub fn simulate_days(
  policy: policy_types.Policy,
  base_context: policy_types.Context,
  start_day: Int,
  end_day: Int,
) -> Result(List(SimulationRow), SimulationError) {
  case start_day <= end_day {
    False -> Error(InvalidRange)
    True -> simulate_loop(policy, base_context, start_day, end_day, [])
  }
}

// Why: simulation should mirror runtime grace handling and preserve action-level
// visibility so policy review is not reduced to bare stage IDs.
fn simulate_loop(
  policy: policy_types.Policy,
  base_context: policy_types.Context,
  day: Int,
  end_day: Int,
  acc: List(SimulationRow),
) -> Result(List(SimulationRow), SimulationError) {
  case day > end_day {
    True -> Ok(list.reverse(acc))
    False ->
      case matches_for_day(policy, base_context, day) {
        Ok(matches) ->
          simulate_loop(policy, base_context, day + 1, end_day, [
            SimulationRow(day:, matches:),
            ..acc
          ])
        Error(error) -> Error(error)
      }
  }
}

fn matches_for_day(
  policy: policy_types.Policy,
  base_context: policy_types.Context,
  day: Int,
) -> Result(List(SimulationMatch), SimulationError) {
  let policy_types.Policy(
    name: _name,
    description: _description,
    grace_days: grace_days,
    timezone: _timezone,
    context: _policy_context,
    stages: _stages,
  ) = policy

  case day <= grace_days {
    True -> Ok([])
    False -> {
      let policy_types.Context(
        days_past_due: _current_day,
        invoice_status: invoice_status,
        operational_state: operational_state,
        billing_plan: billing_plan,
        total_due_amount: total_due_amount,
        is_paid: is_paid,
      ) = base_context

      let context =
        policy_types.Context(
          days_past_due: day,
          invoice_status: invoice_status,
          operational_state: operational_state,
          billing_plan: billing_plan,
          total_due_amount: total_due_amount,
          is_paid: is_paid,
        )

      case policy_evaluator.evaluate(policy, context) {
        Ok(policy_evaluator.EvaluationResult(matches: matches)) ->
          Ok(extract_matches(matches, []))
        Error(error) -> Error(EvaluationFailed(error))
      }
    }
  }
}

// Extracts stage IDs plus actions/reason for deterministic simulation output.
fn extract_matches(
  matches: List(policy_evaluator.StageMatch),
  acc: List(SimulationMatch),
) -> List(SimulationMatch) {
  case matches {
    [] -> list.reverse(acc)
    [policy_evaluator.StageMatch(stage_id:, actions:), ..rest] ->
      extract_matches(rest, [
        SimulationMatch(
          stage_id: stage_id,
          actions: actions,
          reason: "when_condition_matched",
        ),
        ..acc
      ])
  }
}
