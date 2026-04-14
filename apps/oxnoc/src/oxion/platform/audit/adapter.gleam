import gleam/list
import gleam/option
import oxion/orchestration/collection/audit as collection_audit
import oxion/platform/audit/types
import oxion/policy/types as policy_types

pub fn from_collection_entry(
  entry: collection_audit.AuditEntry,
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> types.AuditEnvelope {
  let collection_audit.AuditEntry(
    tenant_id: tenant_id,
    subscriber_id: subscriber_id,
    service_id: service_id,
    invoice_id: invoice_id,
    stage_id: stage_id,
    action_name: action_name,
    action_fingerprint: action_fingerprint,
    command_name: command_name,
    target_state: target_state,
    result_type: result_type,
    reason: reason,
    retry_count: retry_count,
  ) = entry
  let event_id = "audit:" <> action_fingerprint
  let audit_event =
    types.AuditEvent(
      id: event_id,
      tenant_id: tenant_id,
      actor_id: actor_id(runtime_context),
      actor_role: actor_role(runtime_context),
      action: action_name,
      resource_type: "collection_command",
      resource_ref: option.Some(service_id),
      subject_ref: option.Some(subscriber_id),
      subject_alias: option.Some(subject_alias(tenant_id, subscriber_id)),
      change_summary: change_summary(
        stage_id,
        invoice_id,
        action_fingerprint,
        command_name,
        target_state,
        result_type,
        reason,
        retry_count,
      ),
      privacy_class: privacy_class(runtime_context),
      retention_class: types.LongAudit,
      legal_basis: types.LegitimateInterest,
      success: result_type == "success" || result_type == "idempotent_skip",
      error_code: error_code(result_type),
      recorded_at: recorded_at(runtime_context),
    )

  types.AuditEnvelope(
    event: audit_event,
    private_context: private_context(event_id, runtime_context),
  )
}

// Why: the immutable audit stream should only retain a redacted business delta,
// while runtime network context is moved to a short-retention private side store.
fn change_summary(
  stage_id: String,
  invoice_id: String,
  action_fingerprint: String,
  command_name: String,
  target_state: String,
  result_type: String,
  reason: option.Option(String),
  retry_count: Int,
) -> policy_types.JsonValue {
  policy_types.JsonObject([
    #("stage_id", policy_types.JsonString(stage_id)),
    #("invoice_ref", policy_types.JsonString(invoice_id)),
    #("action_fingerprint", policy_types.JsonString(action_fingerprint)),
    #("command_name", policy_types.JsonString(command_name)),
    #("target_state", policy_types.JsonString(target_state)),
    #("result_type", policy_types.JsonString(result_type)),
    #("retry_count", policy_types.JsonInt(retry_count)),
    #("reason", optional_string(reason)),
  ])
}

fn private_context(
  audit_id: String,
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> option.Option(types.AuditPrivateContext) {
  case runtime_context {
    option.None -> option.None
    option.Some(context) -> {
      let payload = private_context_payload(context)

      case payload {
        [] -> option.None
        entries -> {
          let types.RuntimeAuditContext(
            actor_id: _actor_id,
            actor_role: _actor_role,
            ip_address: _ip_address,
            user_agent: _user_agent,
            recorded_at: _recorded_at,
            private_context_expires_at: private_context_expires_at,
          ) = context

          option.Some(types.AuditPrivateContext(
            audit_id: audit_id,
            purpose: "runtime_network_context",
            payload: policy_types.JsonObject(entries),
            expires_at: private_context_expires_at,
          ))
        }
      }
    }
  }
}

fn private_context_payload(
  context: types.RuntimeAuditContext,
) -> List(#(String, policy_types.JsonValue)) {
  let types.RuntimeAuditContext(
    actor_id: _actor_id,
    actor_role: _actor_role,
    ip_address: ip_address,
    user_agent: user_agent,
    recorded_at: _recorded_at,
    private_context_expires_at: _private_context_expires_at,
  ) = context

  add_optional_string(
    "user_agent",
    user_agent,
    add_optional_string("ip_address", ip_address, []),
  )
  |> list.reverse
}

fn add_optional_string(
  name: String,
  value: option.Option(String),
  acc: List(#(String, policy_types.JsonValue)),
) -> List(#(String, policy_types.JsonValue)) {
  case value {
    option.None -> acc
    option.Some(text) -> [#(name, policy_types.JsonString(text)), ..acc]
  }
}

fn subject_alias(tenant_id: String, subscriber_id: String) -> String {
  "subject:" <> tenant_id <> ":" <> subscriber_id
}

fn recorded_at(
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> String {
  case runtime_context {
    option.None -> "unspecified"
    option.Some(context) -> {
      let types.RuntimeAuditContext(
        actor_id: _actor_id,
        actor_role: _actor_role,
        ip_address: _ip_address,
        user_agent: _user_agent,
        recorded_at: recorded_at,
        private_context_expires_at: _private_context_expires_at,
      ) = context

      recorded_at
    }
  }
}

fn actor_id(
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> option.Option(String) {
  case runtime_context {
    option.None -> option.None
    option.Some(context) -> {
      let types.RuntimeAuditContext(
        actor_id: actor_id,
        actor_role: _actor_role,
        ip_address: _ip_address,
        user_agent: _user_agent,
        recorded_at: _recorded_at,
        private_context_expires_at: _private_context_expires_at,
      ) = context

      actor_id
    }
  }
}

fn actor_role(
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> String {
  case runtime_context {
    option.None -> "system"
    option.Some(context) -> {
      let types.RuntimeAuditContext(
        actor_id: _actor_id,
        actor_role: actor_role,
        ip_address: _ip_address,
        user_agent: _user_agent,
        recorded_at: _recorded_at,
        private_context_expires_at: _private_context_expires_at,
      ) = context

      actor_role
    }
  }
}

fn privacy_class(
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> types.PrivacyClass {
  case private_context("classify", runtime_context) {
    option.Some(_) -> types.SensitiveOperationalContext
    option.None -> types.PseudonymisedOperationalData
  }
}

fn error_code(result_type: String) -> option.Option(String) {
  case result_type {
    "failed" -> option.Some("command_failed")
    _ -> option.None
  }
}

fn optional_string(value: option.Option(String)) -> policy_types.JsonValue {
  case value {
    option.None -> policy_types.JsonNull
    option.Some(text) -> policy_types.JsonString(text)
  }
}
