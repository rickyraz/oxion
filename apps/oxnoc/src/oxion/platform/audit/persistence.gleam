import gleam/list
import gleam/option
import oxion/platform/audit/types
import oxion/policy/types as policy_types

pub type PersistenceError {
  DuplicateAuditEventId(id: String)
  DuplicatePrivateContext(audit_id: String)
}

pub type AuditLogRow {
  AuditLogRow(
    id: String,
    tenant_id: String,
    actor_id: option.Option(String),
    actor_role: String,
    action: String,
    resource_type: String,
    resource_ref: option.Option(String),
    subject_ref: option.Option(String),
    subject_alias: option.Option(String),
    change_summary: policy_types.JsonValue,
    privacy_class: types.PrivacyClass,
    retention_class: types.RetentionClass,
    legal_basis: types.LegalBasis,
    success: Bool,
    error_code: option.Option(String),
    recorded_at: String,
  )
}

pub type AuditPrivateContextRow {
  AuditPrivateContextRow(
    audit_id: String,
    purpose: String,
    payload: policy_types.JsonValue,
    expires_at: String,
  )
}

pub type AuditStore {
  AuditStore(
    audit_log: List(AuditLogRow),
    private_context: List(AuditPrivateContextRow),
  )
}

pub fn empty() -> AuditStore {
  AuditStore(audit_log: [], private_context: [])
}

pub fn persist(
  store: AuditStore,
  envelope: types.AuditEnvelope,
) -> Result(AuditStore, PersistenceError) {
  let types.AuditEnvelope(event: event, private_context: private_context) =
    envelope

  case has_event_id(store, event.id) {
    True -> Error(DuplicateAuditEventId(id: event.id))
    False ->
      case has_private_context(private_context, store) {
        True -> Error(DuplicatePrivateContext(audit_id: event.id))
        False -> Ok(insert_envelope(store, event, private_context))
      }
  }
}

pub fn list_audit_log(store: AuditStore, tenant_id: String) -> List(AuditLogRow) {
  let AuditStore(audit_log: audit_log, private_context: _private_context) =
    store

  list.filter(audit_log, fn(row) { row.tenant_id == tenant_id })
}

pub fn find_private_context(
  store: AuditStore,
  audit_id: String,
) -> option.Option(AuditPrivateContextRow) {
  let AuditStore(audit_log: _audit_log, private_context: private_context) =
    store

  case list.filter(private_context, fn(row) { row.audit_id == audit_id }) {
    [row, ..] -> option.Some(row)
    [] -> option.None
  }
}

fn insert_envelope(
  store: AuditStore,
  event: types.AuditEvent,
  private_context: option.Option(types.AuditPrivateContext),
) -> AuditStore {
  let AuditStore(audit_log: audit_log, private_context: private_rows) = store
  let updated_private_rows = case private_context {
    option.None -> private_rows
    option.Some(context) -> [private_context_row(context), ..private_rows]
  }

  AuditStore(
    audit_log: [audit_log_row(event), ..audit_log],
    private_context: updated_private_rows,
  )
}

fn has_event_id(store: AuditStore, id: String) -> Bool {
  let AuditStore(audit_log: audit_log, private_context: _private_context) =
    store

  list.any(audit_log, fn(row) { row.id == id })
}

fn has_private_context(
  private_context: option.Option(types.AuditPrivateContext),
  store: AuditStore,
) -> Bool {
  case private_context {
    option.None -> False
    option.Some(context) -> {
      let AuditStore(audit_log: _audit_log, private_context: private_rows) =
        store

      list.any(private_rows, fn(row) { row.audit_id == context.audit_id })
    }
  }
}

fn audit_log_row(event: types.AuditEvent) -> AuditLogRow {
  let types.AuditEvent(
    id: id,
    tenant_id: tenant_id,
    actor_id: actor_id,
    actor_role: actor_role,
    action: action,
    resource_type: resource_type,
    resource_ref: resource_ref,
    subject_ref: subject_ref,
    subject_alias: subject_alias,
    change_summary: change_summary,
    privacy_class: privacy_class,
    retention_class: retention_class,
    legal_basis: legal_basis,
    success: success,
    error_code: error_code,
    recorded_at: recorded_at,
  ) = event

  AuditLogRow(
    id: id,
    tenant_id: tenant_id,
    actor_id: actor_id,
    actor_role: actor_role,
    action: action,
    resource_type: resource_type,
    resource_ref: resource_ref,
    subject_ref: subject_ref,
    subject_alias: subject_alias,
    change_summary: change_summary,
    privacy_class: privacy_class,
    retention_class: retention_class,
    legal_basis: legal_basis,
    success: success,
    error_code: error_code,
    recorded_at: recorded_at,
  )
}

fn private_context_row(
  private_context: types.AuditPrivateContext,
) -> AuditPrivateContextRow {
  let types.AuditPrivateContext(
    audit_id: audit_id,
    purpose: purpose,
    payload: payload,
    expires_at: expires_at,
  ) = private_context

  AuditPrivateContextRow(
    audit_id: audit_id,
    purpose: purpose,
    payload: payload,
    expires_at: expires_at,
  )
}
