import gleam/list
import gleam/option
import oxion/orchestration/collection/audit as collection_audit
import oxion/platform/audit/adapter
import oxion/platform/audit/types
import oxion/policy/types as policy_types

pub fn audit_adapter_emits_redacted_collection_event_test() {
  let envelope = adapter.from_collection_entry(sample_entry(), option.None)

  assert envelope
    == types.AuditEnvelope(
      event: types.AuditEvent(
        id: "audit:fp:soft:0",
        tenant_id: "tenant_a",
        actor_id: option.None,
        actor_role: "system",
        action: "apply_bandwidth_profile",
        resource_type: "collection_command",
        resource_ref: option.Some("svc_1"),
        subject_ref: option.Some("sub_1"),
        subject_alias: option.Some("subject:tenant_a:sub_1"),
        change_summary: policy_types.JsonObject([
          #("stage_id", policy_types.JsonString("soft_throttle")),
          #("invoice_ref", policy_types.JsonString("inv_1")),
          #("action_fingerprint", policy_types.JsonString("fp:soft:0")),
          #("command_name", policy_types.JsonString("ChangePackage")),
          #("target_state", policy_types.JsonString("throttled_due_overdue")),
          #("result_type", policy_types.JsonString("success")),
          #("retry_count", policy_types.JsonInt(1)),
          #("reason", policy_types.JsonNull),
        ]),
        privacy_class: types.PseudonymisedOperationalData,
        retention_class: types.LongAudit,
        legal_basis: types.LegitimateInterest,
        success: True,
        error_code: option.None,
        recorded_at: "unspecified",
      ),
      private_context: option.None,
    )
}

pub fn audit_adapter_moves_runtime_network_context_to_private_store_test() {
  let runtime_context =
    types.RuntimeAuditContext(
      actor_id: option.Some("ops_123"),
      actor_role: "operator",
      ip_address: option.Some("10.10.10.10"),
      user_agent: option.Some("Mozilla/5.0"),
      recorded_at: "2026-03-21T10:00:00Z",
      private_context_expires_at: "2026-04-20T10:00:00Z",
    )
  let envelope =
    adapter.from_collection_entry(failed_entry(), option.Some(runtime_context))

  assert envelope
    == types.AuditEnvelope(
      event: types.AuditEvent(
        id: "audit:fp:hard:0",
        tenant_id: "tenant_a",
        actor_id: option.Some("ops_123"),
        actor_role: "operator",
        action: "suspend_service",
        resource_type: "collection_command",
        resource_ref: option.Some("svc_1"),
        subject_ref: option.Some("sub_1"),
        subject_alias: option.Some("subject:tenant_a:sub_1"),
        change_summary: policy_types.JsonObject([
          #("stage_id", policy_types.JsonString("hard_suspend")),
          #("invoice_ref", policy_types.JsonString("inv_1")),
          #("action_fingerprint", policy_types.JsonString("fp:hard:0")),
          #("command_name", policy_types.JsonString("SuspendService")),
          #("target_state", policy_types.JsonString("suspended_due_overdue")),
          #("result_type", policy_types.JsonString("failed")),
          #("retry_count", policy_types.JsonInt(2)),
          #("reason", policy_types.JsonString("timeout")),
        ]),
        privacy_class: types.SensitiveOperationalContext,
        retention_class: types.LongAudit,
        legal_basis: types.LegitimateInterest,
        success: False,
        error_code: option.Some("command_failed"),
        recorded_at: "2026-03-21T10:00:00Z",
      ),
      private_context: option.Some(types.AuditPrivateContext(
        audit_id: "audit:fp:hard:0",
        purpose: "runtime_network_context",
        payload: policy_types.JsonObject([
          #("ip_address", policy_types.JsonString("10.10.10.10")),
          #("user_agent", policy_types.JsonString("Mozilla/5.0")),
        ]),
        expires_at: "2026-04-20T10:00:00Z",
      )),
    )
}

pub fn audit_adapter_keeps_append_only_log_redacted_test() {
  let runtime_context =
    types.RuntimeAuditContext(
      actor_id: option.Some("ops_123"),
      actor_role: "operator",
      ip_address: option.Some("10.10.10.10"),
      user_agent: option.Some("Mozilla/5.0"),
      recorded_at: "2026-03-21T10:00:00Z",
      private_context_expires_at: "2026-04-20T10:00:00Z",
    )
  let envelope =
    adapter.from_collection_entry(failed_entry(), option.Some(runtime_context))
  let types.AuditEnvelope(event: event, private_context: private_context) =
    envelope

  let change_summary_entries = json_object_entries(event.change_summary)

  assert has_key(change_summary_entries, "ip_address") == False
  assert has_key(change_summary_entries, "user_agent") == False

  case private_context {
    option.None -> panic
    option.Some(types.AuditPrivateContext(payload: payload, ..)) -> {
      let payload_entries = json_object_entries(payload)

      assert has_key(payload_entries, "ip_address")
      assert has_key(payload_entries, "user_agent")
    }
  }
}

fn sample_entry() -> collection_audit.AuditEntry {
  collection_audit.AuditEntry(
    tenant_id: "tenant_a",
    subscriber_id: "sub_1",
    service_id: "svc_1",
    invoice_id: "inv_1",
    stage_id: "soft_throttle",
    action_name: "apply_bandwidth_profile",
    action_fingerprint: "fp:soft:0",
    command_name: "ChangePackage",
    target_state: "throttled_due_overdue",
    result_type: "success",
    reason: option.None,
    retry_count: 1,
  )
}

fn failed_entry() -> collection_audit.AuditEntry {
  collection_audit.AuditEntry(
    tenant_id: "tenant_a",
    subscriber_id: "sub_1",
    service_id: "svc_1",
    invoice_id: "inv_1",
    stage_id: "hard_suspend",
    action_name: "suspend_service",
    action_fingerprint: "fp:hard:0",
    command_name: "SuspendService",
    target_state: "suspended_due_overdue",
    result_type: "failed",
    reason: option.Some("timeout"),
    retry_count: 2,
  )
}

fn json_object_entries(
  value: policy_types.JsonValue,
) -> List(#(String, policy_types.JsonValue)) {
  case value {
    policy_types.JsonObject(entries) -> entries
    _ -> panic
  }
}

fn has_key(
  entries: List(#(String, policy_types.JsonValue)),
  key: String,
) -> Bool {
  list.any(entries, fn(entry) {
    let #(name, _value) = entry
    name == key
  })
}
