import gleam/option
import oxion/policy/types as policy_types

pub type EnforcementTarget {
  RadiusOnly
  RadiusPlusOlt
  CustomEnforcementTarget(value: String)
}

pub type CommandRoute {
  RadiusRoute
  OltRoute
}

pub type ServiceIdentity {
  ServiceIdentity(
    tenant_id: String,
    subscriber_id: String,
    service_id: String,
    invoice_id: String,
  )
}

pub type CollectionCommand {
  ChangePackage(service_id: String, target_profile_id: String)
  SuspendService(service_id: String, reason: String)
  RestoreService(service_id: String, original_profile_id: String)
}

pub type SideEffectPlan {
  NotificationPlan(
    stage_id: String,
    template_id: String,
    include_payment_link: Bool,
    channels: List(policy_types.NotificationChannel),
    action_fingerprint: String,
  )
  EventPlan(
    stage_id: String,
    topic: String,
    payload: option.Option(policy_types.JsonValue),
    action_fingerprint: String,
  )
  PluginHookPlan(
    stage_id: String,
    plugin_id: String,
    hook: String,
    payload: option.Option(policy_types.JsonValue),
    action_fingerprint: String,
  )
  OperationalStateHintPlan(
    stage_id: String,
    state: String,
    action_fingerprint: String,
  )
}

pub type CommandPlan {
  CommandPlan(
    action_fingerprint: String,
    stage_id: String,
    action_name: String,
    route: CommandRoute,
    command: CollectionCommand,
    target_state: String,
  )
}
