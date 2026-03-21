import gleam/option
import oxion/radius/vendor/types as vendor_types

pub type ActiveSession {
  ActiveSession(
    tenant_id: String,
    service_id: String,
    username: option.Option(String),
    acct_session_id: option.Option(String),
    framed_ip: option.Option(String),
    nas_ip_address: option.Option(String),
    nas_identifier: option.Option(String),
    active_profile_id: option.Option(String),
    attributes: List(vendor_types.RadiusAttribute),
    last_accounting_epoch_seconds: Int,
    session_active: Bool,
  )
}

pub type SessionLookup {
  SessionLookup(
    tenant_id: String,
    service_id: String,
    username: option.Option(String),
    acct_session_id: option.Option(String),
    framed_ip: option.Option(String),
  )
}

pub type SessionResolutionError {
  NoActiveSession
  AmbiguousSession
  StaleSession(max_age_seconds: Int)
}
