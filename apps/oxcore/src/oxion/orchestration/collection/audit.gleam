import gleam/option
import oxion/orchestration/collection/commands
import oxion/orchestration/collection/outcome

pub type AuditEntry {
  AuditEntry(
    tenant_id: String,
    subscriber_id: String,
    service_id: String,
    invoice_id: String,
    stage_id: String,
    action_name: String,
    action_fingerprint: String,
    command_name: String,
    target_state: String,
    result_type: String,
    reason: option.Option(String),
    retry_count: Int,
  )
}

pub fn from_command_outcome(
  service: commands.ServiceIdentity,
  plan: commands.CommandPlan,
  command_outcome: outcome.CommandOutcome,
) -> AuditEntry {
  let commands.ServiceIdentity(
    tenant_id: tenant_id,
    subscriber_id: subscriber_id,
    service_id: service_id,
    invoice_id: invoice_id,
  ) = service
  let commands.CommandPlan(
    action_fingerprint: _plan_fingerprint,
    stage_id: _plan_stage_id,
    action_name: _plan_action_name,
    route: _plan_route,
    command: command,
    target_state: _plan_target_state,
  ) = plan
  let outcome.CommandOutcome(
    action_fingerprint: action_fingerprint,
    stage_id: stage_id,
    action_name: action_name,
    target_state: target_state,
    status: status,
    reason: reason,
    retry_count: retry_count,
  ) = command_outcome

  AuditEntry(
    tenant_id: tenant_id,
    subscriber_id: subscriber_id,
    service_id: service_id,
    invoice_id: invoice_id,
    stage_id: stage_id,
    action_name: action_name,
    action_fingerprint: action_fingerprint,
    command_name: command_name(command),
    target_state: target_state,
    result_type: result_type(status),
    reason: reason,
    retry_count: retry_count,
  )
}

fn command_name(command: commands.CollectionCommand) -> String {
  case command {
    commands.ChangePackage(_, _) -> "ChangePackage"
    commands.SuspendService(_, _) -> "SuspendService"
    commands.RestoreService(_, _) -> "RestoreService"
  }
}

fn result_type(status: outcome.ExecutionStatus) -> String {
  case status {
    outcome.Succeeded -> "success"
    outcome.Failed -> "failed"
    outcome.SkippedIdempotent -> "idempotent_skip"
  }
}
