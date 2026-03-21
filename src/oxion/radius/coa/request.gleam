import oxion/orchestration/collection/commands
import oxion/radius/profile/snapshot
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

pub type BuildError {
  MissingSessionSelector
  EmptyTargetAttributes
}

pub type CoaRequest {
  CoaRequest(
    packet_type: String,
    reason: String,
    action_fingerprint: String,
    session_selector: snapshot.SessionSelector,
    attributes: List(vendor_types.RadiusAttribute),
    disconnect_hint: Bool,
  )
}

pub fn build_request(
  plan: commands.CommandPlan,
  selector: snapshot.SessionSelector,
  target: types.ResolvedTarget,
) -> Result(CoaRequest, BuildError) {
  let commands.CommandPlan(
    action_fingerprint: action_fingerprint,
    stage_id: _stage_id,
    action_name: _action_name,
    route: _route,
    command: command,
    target_state: _target_state,
  ) = plan
  let types.ResolvedTarget(target_id: _target_id, attributes: attributes) =
    target

  case snapshot.validate_selector(selector) {
    Error(snapshot.MissingSessionSelector) -> Error(MissingSessionSelector)
    Ok(_) ->
      case attributes {
        [] -> Error(EmptyTargetAttributes)
        _ ->
          Ok(CoaRequest(
            packet_type: "CoA-Request",
            reason: request_reason(command),
            action_fingerprint: action_fingerprint,
            session_selector: selector,
            attributes: attributes,
            disconnect_hint: disconnect_hint(command),
          ))
      }
  }
}

fn request_reason(command: commands.CollectionCommand) -> String {
  case command {
    commands.ChangePackage(_, _) -> "collection_soft_throttle"
    commands.SuspendService(_, _) -> "collection_hard_suspend"
    commands.RestoreService(_, _) -> "payment_received_restore"
  }
}

fn disconnect_hint(command: commands.CollectionCommand) -> Bool {
  case command {
    commands.SuspendService(_, _) -> True
    _ -> False
  }
}
