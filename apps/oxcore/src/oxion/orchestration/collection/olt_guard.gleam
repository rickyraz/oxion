import gleam/list
import oxion/orchestration/collection/commands

pub type OltGuardError {
  OltMutationBlocked(reason: String)
  UnknownEnforcementTarget(value: String)
}

// Why: the default overdue mode is explicitly radius-only, so any OLT route
// must fail closed before execution can touch a network device.
pub fn validate_plans(
  target: commands.EnforcementTarget,
  plans: List(commands.CommandPlan),
) -> Result(List(commands.CommandPlan), OltGuardError) {
  validate_loop(target, plans, [])
}

fn validate_loop(
  target: commands.EnforcementTarget,
  remaining: List(commands.CommandPlan),
  acc: List(commands.CommandPlan),
) -> Result(List(commands.CommandPlan), OltGuardError) {
  case remaining {
    [] -> Ok(list.reverse(acc))
    [plan, ..rest] ->
      case validate_plan(target, plan) {
        Ok(allowed_plan) -> validate_loop(target, rest, [allowed_plan, ..acc])
        Error(error) -> Error(error)
      }
  }
}

pub fn validate_plan(
  target: commands.EnforcementTarget,
  plan: commands.CommandPlan,
) -> Result(commands.CommandPlan, OltGuardError) {
  let commands.CommandPlan(
    action_fingerprint: _action_fingerprint,
    stage_id: _stage_id,
    action_name: _action_name,
    route: route,
    command: _command,
    target_state: _target_state,
  ) = plan

  case target {
    commands.RadiusOnly ->
      case route {
        commands.RadiusRoute -> Ok(plan)
        commands.OltRoute ->
          Error(OltMutationBlocked(reason: "radius_only_blocks_olt_mutation"))
      }

    commands.RadiusPlusOlt -> Ok(plan)

    commands.CustomEnforcementTarget(value) ->
      Error(UnknownEnforcementTarget(value: value))
  }
}
