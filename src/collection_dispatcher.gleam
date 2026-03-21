import collection_idempotency
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string
import policy_evaluator
import policy_types

pub type DispatchedAction {
  DispatchedAction(
    stage_id: String,
    action_name: String,
    action_identity: String,
    action_position: Int,
    fingerprint: String,
  )
}

pub type DispatchOutcome {
  DispatchOutcome(
    executed: List(DispatchedAction),
    skipped: List(DispatchedAction),
    fingerprints: List(String),
  )
}

/// Dispatches matched policy actions with idempotency safeguards.
pub fn dispatch_matches(
  tenant_id: String,
  subscriber_id: String,
  invoice_id: String,
  matches: List(policy_evaluator.StageMatch),
  existing_fingerprints: List(String),
) -> DispatchOutcome {
  dispatch_loop(
    tenant_id,
    subscriber_id,
    invoice_id,
    matches,
    existing_fingerprints,
    [],
    [],
  )
}

// Iterates stage matches and dispatches all actions per stage.
fn dispatch_loop(
  tenant_id: String,
  subscriber_id: String,
  invoice_id: String,
  matches: List(policy_evaluator.StageMatch),
  fingerprints: List(String),
  executed_acc: List(DispatchedAction),
  skipped_acc: List(DispatchedAction),
) -> DispatchOutcome {
  case matches {
    [] ->
      DispatchOutcome(
        executed: list.reverse(executed_acc),
        skipped: list.reverse(skipped_acc),
        fingerprints: fingerprints,
      )

    [policy_evaluator.StageMatch(stage_id:, actions:), ..rest] -> {
      let #(next_fingerprints, next_executed, next_skipped) =
        dispatch_actions(
          tenant_id,
          subscriber_id,
          invoice_id,
          stage_id,
          actions,
          0,
          fingerprints,
          executed_acc,
          skipped_acc,
        )

      dispatch_loop(
        tenant_id,
        subscriber_id,
        invoice_id,
        rest,
        next_fingerprints,
        next_executed,
        next_skipped,
      )
    }
  }
}

// Why: fingerprints need stable per-action identity plus position so two actions
// of the same type in one stage do not collapse into a fake duplicate.
fn dispatch_actions(
  tenant_id: String,
  subscriber_id: String,
  invoice_id: String,
  stage_id: String,
  actions: List(policy_types.Action),
  action_position: Int,
  fingerprints: List(String),
  executed_acc: List(DispatchedAction),
  skipped_acc: List(DispatchedAction),
) -> #(List(String), List(DispatchedAction), List(DispatchedAction)) {
  case actions {
    [] -> #(fingerprints, executed_acc, skipped_acc)
    [action, ..rest] -> {
      let action_name = action_to_name(action)
      let identity = action_identity(action)
      let fp =
        collection_idempotency.action_fingerprint(
          tenant_id,
          subscriber_id,
          invoice_id,
          stage_id,
          action_position,
          identity,
        )

      let record =
        DispatchedAction(
          stage_id: stage_id,
          action_name: action_name,
          action_identity: identity,
          action_position: action_position,
          fingerprint: fp,
        )

      case collection_idempotency.should_execute(fingerprints, fp) {
        True ->
          dispatch_actions(
            tenant_id,
            subscriber_id,
            invoice_id,
            stage_id,
            rest,
            action_position + 1,
            collection_idempotency.append_fingerprint(fingerprints, fp),
            [record, ..executed_acc],
            skipped_acc,
          )

        False ->
          dispatch_actions(
            tenant_id,
            subscriber_id,
            invoice_id,
            stage_id,
            rest,
            action_position + 1,
            fingerprints,
            executed_acc,
            [record, ..skipped_acc],
          )
      }
    }
  }
}

/// Converts action variants to normalized action names for logs/fingerprints.
pub fn action_to_name(action: policy_types.Action) -> String {
  case action {
    policy_types.ApplyBandwidthProfile(_) -> "apply_bandwidth_profile"
    policy_types.SuspendService(_) -> "suspend_service"
    policy_types.RestoreService -> "restore_service"
    policy_types.SendNotification(_, _, _) -> "send_notification"
    policy_types.EmitEvent(_, _) -> "emit_event"
    policy_types.SetOperationalState(_) -> "set_operational_state"
    policy_types.RunPluginHook(_, _, _) -> "run_plugin_hook"
  }
}

pub fn action_identity(action: policy_types.Action) -> String {
  case action {
    policy_types.ApplyBandwidthProfile(profile_id) ->
      "apply_bandwidth_profile:" <> profile_id

    policy_types.SuspendService(reason) -> "suspend_service:" <> reason

    policy_types.RestoreService -> "restore_service"

    policy_types.SendNotification(template_id, include_payment_link, channels) ->
      "send_notification:"
      <> template_id
      <> ":"
      <> bool.to_string(include_payment_link)
      <> ":"
      <> channel_identity(channels)

    policy_types.EmitEvent(topic, payload) ->
      "emit_event:" <> topic <> ":" <> payload_identity(payload)

    policy_types.SetOperationalState(state) -> "set_operational_state:" <> state

    policy_types.RunPluginHook(plugin_id, hook, payload) ->
      "run_plugin_hook:"
      <> plugin_id
      <> ":"
      <> hook
      <> ":"
      <> payload_identity(payload)
  }
}

fn channel_identity(channels: List(policy_types.NotificationChannel)) -> String {
  string.join(sort_strings(channel_names(channels, []), []), with: ",")
}

fn channel_names(
  remaining: List(policy_types.NotificationChannel),
  acc: List(String),
) -> List(String) {
  case remaining {
    [] -> list.reverse(acc)
    [channel, ..rest] ->
      channel_names(rest, [channel_to_string(channel), ..acc])
  }
}

fn channel_to_string(channel: policy_types.NotificationChannel) -> String {
  case channel {
    policy_types.Whatsapp -> "whatsapp"
    policy_types.Telegram -> "telegram"
    policy_types.Sms -> "sms"
    policy_types.Email -> "email"
    policy_types.Push -> "push"
  }
}

fn payload_identity(payload: option.Option(policy_types.JsonValue)) -> String {
  case payload {
    option.None -> "none"
    option.Some(value) -> json_identity(value)
  }
}

fn json_identity(value: policy_types.JsonValue) -> String {
  case value {
    policy_types.JsonNull -> "null"
    policy_types.JsonBool(bool_value) -> "bool:" <> bool.to_string(bool_value)
    policy_types.JsonInt(int_value) -> "int:" <> int.to_string(int_value)
    policy_types.JsonFloat(float_value) ->
      "float:" <> float.to_string(float_value)
    policy_types.JsonString(string_value) -> "string:" <> string_value
    policy_types.JsonArray(items) ->
      "array:[" <> array_identity(items, []) <> "]"
    policy_types.JsonObject(entries) ->
      "object:{" <> object_identity(sort_object_entries(entries), []) <> "}"
  }
}

fn array_identity(
  items: List(policy_types.JsonValue),
  acc: List(String),
) -> String {
  case items {
    [] -> string.join(list.reverse(acc), with: ",")
    [item, ..rest] -> array_identity(rest, [json_identity(item), ..acc])
  }
}

fn object_identity(
  entries: List(#(String, policy_types.JsonValue)),
  acc: List(String),
) -> String {
  case entries {
    [] -> string.join(list.reverse(acc), with: ",")
    [#(key, value), ..rest] ->
      object_identity(rest, [key <> "=" <> json_identity(value), ..acc])
  }
}

fn sort_object_entries(
  entries: List(#(String, policy_types.JsonValue)),
) -> List(#(String, policy_types.JsonValue)) {
  sort_object_entries_loop(entries, [])
}

fn sort_object_entries_loop(
  remaining: List(#(String, policy_types.JsonValue)),
  acc: List(#(String, policy_types.JsonValue)),
) -> List(#(String, policy_types.JsonValue)) {
  case remaining {
    [] -> acc
    [entry, ..rest] ->
      sort_object_entries_loop(rest, insert_object_entry(entry, acc))
  }
}

fn insert_object_entry(
  entry: #(String, policy_types.JsonValue),
  sorted: List(#(String, policy_types.JsonValue)),
) -> List(#(String, policy_types.JsonValue)) {
  case sorted {
    [] -> [entry]
    [head, ..tail] ->
      case object_entry_before(entry, head) {
        True -> [entry, head, ..tail]
        False -> [head, ..insert_object_entry(entry, tail)]
      }
  }
}

fn object_entry_before(
  a: #(String, policy_types.JsonValue),
  b: #(String, policy_types.JsonValue),
) -> Bool {
  let #(a_key, _a_value) = a
  let #(b_key, _b_value) = b

  case string.compare(a_key, b_key) {
    order.Lt -> True
    _ -> False
  }
}

fn sort_strings(remaining: List(String), acc: List(String)) -> List(String) {
  case remaining {
    [] -> acc
    [value, ..rest] -> sort_strings(rest, insert_string(value, acc))
  }
}

fn insert_string(value: String, sorted: List(String)) -> List(String) {
  case sorted {
    [] -> [value]
    [head, ..tail] ->
      case string.compare(value, head) {
        order.Lt -> [value, head, ..tail]
        _ -> [head, ..insert_string(value, tail)]
      }
  }
}
