import gleam/list
import gleam/option
import oxion/collection/dispatcher as collection_dispatcher
import oxion/policy/evaluator as policy_evaluator
import oxion/policy/types as policy_types

pub type OverdueCandidate {
  OverdueCandidate(
    tenant_id: String,
    subscriber_id: String,
    invoice_id: String,
    days_past_due: Int,
    invoice_status: String,
    operational_state: String,
    billing_plan: String,
    total_due_amount: Int,
    is_paid: Bool,
  )
}

pub type CandidateExecutionResult {
  CandidateExecutionResult(
    tenant_id: String,
    subscriber_id: String,
    invoice_id: String,
    matched_stage_ids: List(String),
    executed_count: Int,
    skipped_count: Int,
    executed_actions: List(collection_dispatcher.DispatchedAction),
    skipped_actions: List(collection_dispatcher.DispatchedAction),
    evaluation_error: option.Option(policy_evaluator.EvaluationError),
  )
}

pub type SchedulerConfig {
  SchedulerConfig(timezone: String, evaluation_time: option.Option(String))
}

pub type SchedulerRunResult {
  SchedulerRunResult(
    executed_total: Int,
    skipped_total: Int,
    error_total: Int,
    fingerprints: List(String),
    results: List(CandidateExecutionResult),
  )
}

// Why: timezone/evaluation_time are scheduler contract inputs even when the
// pure runner receives preselected candidates from an outer orchestration layer.
pub fn scheduling_config(policy: policy_types.Policy) -> SchedulerConfig {
  let policy_types.Policy(
    name: _name,
    description: _description,
    grace_days: _grace_days,
    timezone: timezone,
    context: context,
    stages: _stages,
  ) = policy

  let evaluation_time = case context {
    option.None -> option.None
    option.Some(config) -> {
      let policy_types.PolicyContextConfig(
        evaluation_time: evaluation_time,
        payment_link_mode: _payment_link_mode,
        payment_link_base_url: _payment_link_base_url,
        payment_link_ttl_minutes: _payment_link_ttl_minutes,
      ) = config
      evaluation_time
    }
  }

  SchedulerConfig(timezone: timezone, evaluation_time: evaluation_time)
}

/// Runs collection enforcement over overdue candidates using evaluator + dispatcher.
pub fn run(
  policy: policy_types.Policy,
  candidates: List(OverdueCandidate),
  existing_fingerprints: List(String),
) -> SchedulerRunResult {
  run_loop(policy, candidates, existing_fingerprints, 0, 0, 0, [])
}

// Why: scheduler output must stay audit-friendly, so each candidate carries the
// exact dispatched actions and any evaluation error instead of silent fallbacks.
fn run_loop(
  policy: policy_types.Policy,
  remaining: List(OverdueCandidate),
  fingerprints: List(String),
  executed_total: Int,
  skipped_total: Int,
  error_total: Int,
  results_acc: List(CandidateExecutionResult),
) -> SchedulerRunResult {
  case remaining {
    [] ->
      SchedulerRunResult(
        executed_total: executed_total,
        skipped_total: skipped_total,
        error_total: error_total,
        fingerprints: fingerprints,
        results: list.reverse(results_acc),
      )

    [candidate, ..rest] -> {
      let OverdueCandidate(
        tenant_id: _tenant_id,
        subscriber_id: _subscriber_id,
        invoice_id: _invoice_id,
        days_past_due: days_past_due,
        invoice_status: invoice_status,
        operational_state: operational_state,
        billing_plan: billing_plan,
        total_due_amount: total_due_amount,
        is_paid: is_paid,
      ) = candidate

      let context =
        policy_types.Context(
          days_past_due: days_past_due,
          invoice_status: invoice_status,
          operational_state: operational_state,
          billing_plan: billing_plan,
          total_due_amount: total_due_amount,
          is_paid: is_paid,
        )

      let #(result, next_fingerprints, next_error_total) =
        execute_candidate(policy, candidate, context, fingerprints, error_total)

      let CandidateExecutionResult(
        tenant_id: _,
        subscriber_id: _,
        invoice_id: _,
        matched_stage_ids: _,
        executed_count: executed_count,
        skipped_count: skipped_count,
        executed_actions: _,
        skipped_actions: _,
        evaluation_error: _,
      ) = result

      run_loop(
        policy,
        rest,
        next_fingerprints,
        executed_total + executed_count,
        skipped_total + skipped_count,
        next_error_total,
        [result, ..results_acc],
      )
    }
  }
}

fn execute_candidate(
  policy: policy_types.Policy,
  candidate: OverdueCandidate,
  context: policy_types.Context,
  fingerprints: List(String),
  error_total: Int,
) -> #(CandidateExecutionResult, List(String), Int) {
  let OverdueCandidate(
    tenant_id: tenant_id,
    subscriber_id: subscriber_id,
    invoice_id: invoice_id,
    days_past_due: days_past_due,
    invoice_status: _invoice_status,
    operational_state: _operational_state,
    billing_plan: _billing_plan,
    total_due_amount: _total_due_amount,
    is_paid: _is_paid,
  ) = candidate

  let policy_types.Policy(
    name: _name,
    description: _description,
    grace_days: grace_days,
    timezone: _timezone,
    context: _policy_context,
    stages: _stages,
  ) = policy

  case days_past_due <= grace_days {
    True -> #(
      empty_result(tenant_id, subscriber_id, invoice_id, option.None),
      fingerprints,
      error_total,
    )

    False ->
      case policy_evaluator.evaluate(policy, context) {
        Ok(policy_evaluator.EvaluationResult(matches: matches)) -> {
          let dispatch_outcome =
            collection_dispatcher.dispatch_matches(
              tenant_id,
              subscriber_id,
              invoice_id,
              matches,
              fingerprints,
            )

          let collection_dispatcher.DispatchOutcome(
            executed: executed,
            skipped: skipped,
            fingerprints: next_fingerprints,
          ) = dispatch_outcome

          #(
            CandidateExecutionResult(
              tenant_id: tenant_id,
              subscriber_id: subscriber_id,
              invoice_id: invoice_id,
              matched_stage_ids: stage_ids_from_matches(matches),
              executed_count: list.length(executed),
              skipped_count: list.length(skipped),
              executed_actions: executed,
              skipped_actions: skipped,
              evaluation_error: option.None,
            ),
            next_fingerprints,
            error_total,
          )
        }

        Error(error) -> #(
          empty_result(tenant_id, subscriber_id, invoice_id, option.Some(error)),
          fingerprints,
          error_total + 1,
        )
      }
  }
}

fn empty_result(
  tenant_id: String,
  subscriber_id: String,
  invoice_id: String,
  evaluation_error: option.Option(policy_evaluator.EvaluationError),
) -> CandidateExecutionResult {
  CandidateExecutionResult(
    tenant_id: tenant_id,
    subscriber_id: subscriber_id,
    invoice_id: invoice_id,
    matched_stage_ids: [],
    executed_count: 0,
    skipped_count: 0,
    executed_actions: [],
    skipped_actions: [],
    evaluation_error: evaluation_error,
  )
}

// Extracts unique stage IDs from evaluator matches.
fn stage_ids_from_matches(
  matches: List(policy_evaluator.StageMatch),
) -> List(String) {
  unique_stage_ids_from_matches(matches, [])
}

// Collects unique stage IDs in deterministic order.
fn unique_stage_ids_from_matches(
  remaining: List(policy_evaluator.StageMatch),
  acc: List(String),
) -> List(String) {
  case remaining {
    [] -> list.reverse(acc)
    [policy_evaluator.StageMatch(stage_id:, actions: _), ..rest] ->
      case list.contains(acc, stage_id) {
        True -> unique_stage_ids_from_matches(rest, acc)
        False -> unique_stage_ids_from_matches(rest, [stage_id, ..acc])
      }
  }
}
