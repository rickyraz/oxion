import gleam/option
import oxion/policy/types as policy_types

pub type PrivacyClass {
  NoPersonalData
  PseudonymisedOperationalData
  DirectPersonalData
  SensitiveOperationalContext
}

pub type RetentionClass {
  ShortOperational
  SecurityForensic
  ConsentEvidence
  FinancialStatutory
  LongAudit
}

pub type LegalBasis {
  Contract
  LegalObligation
  LegitimateInterest
  Consent
  VitalInterest
  PublicTask
}

pub type AuditEvent {
  AuditEvent(
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
    privacy_class: PrivacyClass,
    retention_class: RetentionClass,
    legal_basis: LegalBasis,
    success: Bool,
    error_code: option.Option(String),
    recorded_at: String,
  )
}

pub type AuditPrivateContext {
  AuditPrivateContext(
    audit_id: String,
    purpose: String,
    payload: policy_types.JsonValue,
    expires_at: String,
  )
}

pub type AuditEnvelope {
  AuditEnvelope(
    event: AuditEvent,
    private_context: option.Option(AuditPrivateContext),
  )
}

pub type RuntimeAuditContext {
  RuntimeAuditContext(
    actor_id: option.Option(String),
    actor_role: String,
    ip_address: option.Option(String),
    user_agent: option.Option(String),
    recorded_at: String,
    private_context_expires_at: String,
  )
}
