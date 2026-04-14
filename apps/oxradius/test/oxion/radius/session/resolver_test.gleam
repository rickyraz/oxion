import gleam/option
import oxion/radius/session/resolver
import oxion/radius/session/types
import oxion/radius/vendor/types as vendor_types

pub fn session_resolver_returns_fresh_session_test() {
  let session = sample_session()

  assert resolver.resolve_active_session(
      [session],
      types.SessionLookup(
        tenant_id: "tenant_a",
        service_id: "svc_1",
        username: option.Some("cust_001"),
        acct_session_id: option.None,
        framed_ip: option.None,
      ),
      60,
      120,
    )
    == Ok(session)
}

pub fn session_resolver_projects_snapshot_test() {
  let snapshot = resolver.to_snapshot(sample_session())

  assert snapshot.profile_id == option.Some("bw_4mbps")
}

fn sample_session() -> types.ActiveSession {
  types.ActiveSession(
    tenant_id: "tenant_a",
    service_id: "svc_1",
    username: option.Some("cust_001"),
    acct_session_id: option.Some("sess-1"),
    framed_ip: option.Some("10.10.20.5"),
    nas_ip_address: option.Some("10.0.0.1"),
    nas_identifier: option.None,
    active_profile_id: option.Some("bw_4mbps"),
    attributes: [vendor_types.RadiusAttribute(name: "class", value: "normal")],
    last_accounting_epoch_seconds: 100,
    session_active: True,
  )
}
