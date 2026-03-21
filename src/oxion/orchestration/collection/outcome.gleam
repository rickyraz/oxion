import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/result as coa_result

pub type ExecutionStatus {
  Succeeded
  Failed
  SkippedIdempotent
}

pub type CommandOutcome {
  CommandOutcome(
    action_fingerprint: String,
    stage_id: String,
    action_name: String,
    target_state: String,
    status: ExecutionStatus,
    reason: option.Option(String),
    retry_count: Int,
  )
}

pub fn from_radius_execution(
  plan: commands.CommandPlan,
  result: coa_result.CoaExecutionResult,
) -> CommandOutcome {
  let commands.CommandPlan(
    action_fingerprint: action_fingerprint,
    stage_id: stage_id,
    action_name: action_name,
    route: _route,
    command: _command,
    target_state: target_state,
  ) = plan

  CommandOutcome(
    action_fingerprint: action_fingerprint,
    stage_id: stage_id,
    action_name: action_name,
    target_state: target_state,
    status: map_status(result),
    reason: coa_result.reason(result),
    retry_count: coa_result.retry_count(result),
  )
}

fn map_status(result: coa_result.CoaExecutionResult) -> ExecutionStatus {
  case result {
    coa_result.IdempotentSkip(_) -> SkippedIdempotent
    coa_result.Ack(_, _) -> Succeeded
    _ -> Failed
  }
}
