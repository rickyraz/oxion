import gleam/option
import oxion/orchestration/collection/audit as collection_audit
import oxion/platform/audit/adapter
import oxion/platform/audit/persistence
import oxion/platform/audit/service
import oxion/platform/audit/types
import oxion/policy/types as policy_types

pub fn audit_persistence_stores_log_and_private_context_rows_test() {
  let envelope =
    adapter.from_collection_entry(
      failed_entry(),
      option.Some(sample_runtime_context()),
    )
  let store = case persistence.persist(persistence.empty(), envelope) {
    Ok(store) -> store
    Error(_) -> panic
  }

  assert persistence.list_audit_log(store, "tenant_a")
    == [
      persistence.AuditLogRow(
        id: "audit:fp:hard:0",
        tenant_id: "tenant_a",
        actor_id: option.Some("ops_123"),
        actor_role: "operator",
        action: "suspend_service",
        resource_type: "collection_command",
        resource_ref: option.Some("svc_1"),
        subject_ref: option.Some("sub_1"),
        subject_alias: option.Some("subject:tenant_a:sub_1"),
        change_summary: envelope.event.change_summary,
        privacy_class: types.SensitiveOperationalContext,
        retention_class: types.LongAudit,
        legal_basis: types.LegitimateInterest,
        success: False,
        error_code: option.Some("command_failed"),
        recorded_at: "2026-03-21T10:00:00Z",
      ),
    ]

  assert persistence.find_private_context(store, "audit:fp:hard:0")
    == option.Some(persistence.AuditPrivateContextRow(
      audit_id: "audit:fp:hard:0",
      purpose: "runtime_network_context",
      payload: private_context_payload(envelope),
      expires_at: "2026-04-20T10:00:00Z",
    ))
}

pub fn audit_persistence_rejects_duplicate_event_id_test() {
  let envelope = adapter.from_collection_entry(sample_entry(), option.None)
  let store = case persistence.persist(persistence.empty(), envelope) {
    Ok(store) -> store
    Error(_) -> panic
  }

  assert persistence.persist(store, envelope)
    == Error(persistence.DuplicateAuditEventId(id: "audit:fp:soft:0"))
}

pub fn audit_service_persists_collection_entry_test() {
  let store = case
    service.persist_collection_entry(
      persistence.empty(),
      sample_entry(),
      option.None,
    )
  {
    Ok(store) -> store
    Error(_) -> panic
  }

  assert persistence.list_audit_log(store, "tenant_a")
    == [
      persistence.AuditLogRow(
        id: "audit:fp:soft:0",
        tenant_id: "tenant_a",
        actor_id: option.None,
        actor_role: "system",
        action: "apply_bandwidth_profile",
        resource_type: "collection_command",
        resource_ref: option.Some("svc_1"),
        subject_ref: option.Some("sub_1"),
        subject_alias: option.Some("subject:tenant_a:sub_1"),
        change_summary: adapter.from_collection_entry(
          sample_entry(),
          option.None,
        ).event.change_summary,
        privacy_class: types.PseudonymisedOperationalData,
        retention_class: types.LongAudit,
        legal_basis: types.LegitimateInterest,
        success: True,
        error_code: option.None,
        recorded_at: "unspecified",
      ),
    ]
}

pub fn audit_persistence_expires_private_context_after_retention_window_test() {
  let envelope =
    adapter.from_collection_entry(
      failed_entry(),
      option.Some(sample_runtime_context()),
    )
  let store = case persistence.persist(persistence.empty(), envelope) {
    Ok(store) -> store
    Error(_) -> panic
  }

  let #(before_expiry_store, before_expiry_count) =
    persistence.expire_private_context(store, "2026-04-20T09:59:59Z")

  assert before_expiry_count == 0
  assert persistence.find_private_context(
      before_expiry_store,
      "audit:fp:hard:0",
    )
    == option.Some(persistence.AuditPrivateContextRow(
      audit_id: "audit:fp:hard:0",
      purpose: "runtime_network_context",
      payload: private_context_payload(envelope),
      expires_at: "2026-04-20T10:00:00Z",
    ))

  let #(expired_store, expired_count) =
    persistence.expire_private_context(store, "2026-04-20T10:00:00Z")

  assert expired_count == 1
  assert persistence.find_private_context(expired_store, "audit:fp:hard:0")
    == option.None
}

fn sample_runtime_context() -> types.RuntimeAuditContext {
  types.RuntimeAuditContext(
    actor_id: option.Some("ops_123"),
    actor_role: "operator",
    ip_address: option.Some("10.10.10.10"),
    user_agent: option.Some("Mozilla/5.0"),
    recorded_at: "2026-03-21T10:00:00Z",
    private_context_expires_at: "2026-04-20T10:00:00Z",
  )
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

fn private_context_payload(
  envelope: types.AuditEnvelope,
) -> policy_types.JsonValue {
  let types.AuditEnvelope(event: _event, private_context: private_context) =
    envelope

  case private_context {
    option.Some(types.AuditPrivateContext(
      audit_id: _audit_id,
      purpose: _purpose,
      payload: payload,
      expires_at: _expires_at,
    )) -> payload
    option.None -> panic
  }
}
