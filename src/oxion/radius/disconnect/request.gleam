import oxion/orchestration/collection/commands
import oxion/radius/profile/snapshot

pub type BuildError {
  MissingSessionSelector
  UnsupportedCommand(command_name: String)
}

pub type DisconnectRequest {
  DisconnectRequest(
    packet_type: String,
    reason: String,
    action_fingerprint: String,
    session_selector: snapshot.SessionSelector,
  )
}

pub fn build_request(
  plan: commands.CommandPlan,
  selector: snapshot.SessionSelector,
) -> Result(DisconnectRequest, BuildError) {
  let commands.CommandPlan(
    action_fingerprint: action_fingerprint,
    stage_id: _stage_id,
    action_name: _action_name,
    route: _route,
    command: command,
    target_state: _target_state,
  ) = plan

  case snapshot.validate_selector(selector) {
    Error(snapshot.MissingSessionSelector) -> Error(MissingSessionSelector)
    Ok(_) ->
      case command {
        commands.SuspendService(service_id: _service_id, reason: reason) ->
          Ok(DisconnectRequest(
            packet_type: "Disconnect-Request",
            reason: reason,
            action_fingerprint: action_fingerprint,
            session_selector: selector,
          ))
        commands.ChangePackage(_, _) ->
          Error(UnsupportedCommand(command_name: "ChangePackage"))
        commands.RestoreService(_, _) ->
          Error(UnsupportedCommand(command_name: "RestoreService"))
      }
  }
}
