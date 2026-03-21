import gleam/list
import gleam/option
import oxion/collection/dispatcher
import oxion/orchestration/collection/commands
import oxion/orchestration/collection/olt_guard
import oxion/policy/types as policy_types

pub type OrchestrationError {
  MissingOriginalProfile
  ConflictingTargetState(existing: String, incoming: String)
  GuardRejected(error: olt_guard.OltGuardError)
}

pub type OrchestrationPlan {
  OrchestrationPlan(
    commands: List(commands.CommandPlan),
    side_effects: List(commands.SideEffectPlan),
  )
}

pub fn plan_candidate(
  service: commands.ServiceIdentity,
  executed_actions: List(dispatcher.DispatchedAction),
  original_profile_id: option.Option(String),
  target: commands.EnforcementTarget,
) -> Result(OrchestrationPlan, OrchestrationError) {
  case plan_loop(service, executed_actions, original_profile_id, [], []) {
    Ok(OrchestrationPlan(
      commands: command_plans,
      side_effects: side_effect_plans,
    )) ->
      case olt_guard.validate_plans(target, command_plans) {
        Ok(guarded_plans) ->
          Ok(OrchestrationPlan(
            commands: guarded_plans,
            side_effects: side_effect_plans,
          ))
        Error(error) -> Error(GuardRejected(error: error))
      }

    Error(error) -> Error(error)
  }
}

// Why: collection runtime already decided what executed, so orchestration must
// only translate those actions into command and side-effect plans deterministically.
fn plan_loop(
  service: commands.ServiceIdentity,
  remaining: List(dispatcher.DispatchedAction),
  original_profile_id: option.Option(String),
  command_acc: List(commands.CommandPlan),
  side_effect_acc: List(commands.SideEffectPlan),
) -> Result(OrchestrationPlan, OrchestrationError) {
  case remaining {
    [] ->
      Ok(OrchestrationPlan(
        commands: list.reverse(command_acc),
        side_effects: list.reverse(side_effect_acc),
      ))

    [action, ..rest] ->
      case plan_action(service, action, original_profile_id, command_acc) {
        Ok(#(option.Some(command_plan), option.None)) ->
          plan_loop(
            service,
            rest,
            original_profile_id,
            [command_plan, ..command_acc],
            side_effect_acc,
          )

        Ok(#(option.None, option.Some(side_effect_plan))) ->
          plan_loop(service, rest, original_profile_id, command_acc, [
            side_effect_plan,
            ..side_effect_acc
          ])

        Ok(#(option.None, option.None)) ->
          plan_loop(
            service,
            rest,
            original_profile_id,
            command_acc,
            side_effect_acc,
          )

        Ok(#(option.Some(command_plan), option.Some(side_effect_plan))) ->
          plan_loop(
            service,
            rest,
            original_profile_id,
            [command_plan, ..command_acc],
            [side_effect_plan, ..side_effect_acc],
          )

        Error(error) -> Error(error)
      }
  }
}

fn plan_action(
  service: commands.ServiceIdentity,
  dispatched_action: dispatcher.DispatchedAction,
  original_profile_id: option.Option(String),
  command_acc: List(commands.CommandPlan),
) -> Result(
  #(option.Option(commands.CommandPlan), option.Option(commands.SideEffectPlan)),
  OrchestrationError,
) {
  let dispatcher.DispatchedAction(
    stage_id: stage_id,
    action_name: action_name,
    action_identity: _action_identity,
    action_position: _action_position,
    fingerprint: fingerprint,
    action: action,
  ) = dispatched_action
  let commands.ServiceIdentity(
    tenant_id: _tenant_id,
    subscriber_id: _subscriber_id,
    service_id: service_id,
    invoice_id: _invoice_id,
  ) = service

  case action {
    policy_types.ApplyBandwidthProfile(profile_id) -> {
      let command_plan =
        commands.CommandPlan(
          action_fingerprint: fingerprint,
          stage_id: stage_id,
          action_name: action_name,
          route: commands.RadiusRoute,
          command: commands.ChangePackage(
            service_id: service_id,
            target_profile_id: profile_id,
          ),
          target_state: "throttled_due_overdue",
        )

      append_command_plan(command_acc, command_plan)
    }

    policy_types.SuspendService(reason) -> {
      let command_plan =
        commands.CommandPlan(
          action_fingerprint: fingerprint,
          stage_id: stage_id,
          action_name: action_name,
          route: commands.RadiusRoute,
          command: commands.SuspendService(
            service_id: service_id,
            reason: reason,
          ),
          target_state: "suspended_due_overdue",
        )

      append_command_plan(command_acc, command_plan)
    }

    policy_types.RestoreService ->
      case original_profile_id {
        option.None -> Error(MissingOriginalProfile)
        option.Some(profile_id) -> {
          let command_plan =
            commands.CommandPlan(
              action_fingerprint: fingerprint,
              stage_id: stage_id,
              action_name: action_name,
              route: commands.RadiusRoute,
              command: commands.RestoreService(
                service_id: service_id,
                original_profile_id: profile_id,
              ),
              target_state: "normal",
            )

          append_command_plan(command_acc, command_plan)
        }
      }

    policy_types.SendNotification(template_id, include_payment_link, channels) ->
      Ok(#(
        option.None,
        option.Some(commands.NotificationPlan(
          stage_id: stage_id,
          template_id: template_id,
          include_payment_link: include_payment_link,
          channels: channels,
          action_fingerprint: fingerprint,
        )),
      ))

    policy_types.EmitEvent(topic, payload) ->
      Ok(#(
        option.None,
        option.Some(commands.EventPlan(
          stage_id: stage_id,
          topic: topic,
          payload: payload,
          action_fingerprint: fingerprint,
        )),
      ))

    policy_types.RunPluginHook(plugin_id, hook, payload) ->
      Ok(#(
        option.None,
        option.Some(commands.PluginHookPlan(
          stage_id: stage_id,
          plugin_id: plugin_id,
          hook: hook,
          payload: payload,
          action_fingerprint: fingerprint,
        )),
      ))

    policy_types.SetOperationalState(state) ->
      Ok(#(
        option.None,
        option.Some(commands.OperationalStateHintPlan(
          stage_id: stage_id,
          state: state,
          action_fingerprint: fingerprint,
        )),
      ))
  }
}

fn append_command_plan(
  command_acc: List(commands.CommandPlan),
  new_plan: commands.CommandPlan,
) -> Result(
  #(option.Option(commands.CommandPlan), option.Option(commands.SideEffectPlan)),
  OrchestrationError,
) {
  let commands.CommandPlan(
    action_fingerprint: _action_fingerprint,
    stage_id: _stage_id,
    action_name: _action_name,
    route: _route,
    command: _command,
    target_state: new_state,
  ) = new_plan

  case command_acc {
    [] -> Ok(#(option.Some(new_plan), option.None))
    [existing, ..] -> {
      let commands.CommandPlan(
        action_fingerprint: _existing_fingerprint,
        stage_id: _existing_stage_id,
        action_name: _existing_action_name,
        route: _existing_route,
        command: _existing_command,
        target_state: existing_state,
      ) = existing

      case existing_state == new_state {
        True -> Ok(#(option.Some(new_plan), option.None))
        False ->
          Error(ConflictingTargetState(
            existing: existing_state,
            incoming: new_state,
          ))
      }
    }
  }
}
