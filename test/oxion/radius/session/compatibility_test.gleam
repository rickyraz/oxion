import gleam/option
import oxion/radius/session/compatibility
import oxion/radius/session/types
import oxion/radius/vendor/types as vendor_types

pub fn compatibility_materializes_active_session_from_interim_test() {
  assert compatibility.from_accounting_record(sample_interim_record())
    == Ok(sample_active_session())
}

pub fn compatibility_filters_inactive_records_from_materialized_list_test() {
  assert compatibility.materialize_active_sessions([
      sample_interim_record(),
      sample_stop_record(),
    ])
    == [sample_active_session()]
}

fn sample_interim_record() -> types.AccountingRecord {
  types.AccountingRecord(
    tenant_id: "tenant_a",
    service_id: "svc_1",
    username: option.Some("cust_001"),
    acct_session_id: option.Some("sess-1"),
    framed_ip: option.Some("10.10.20.5"),
    nas_ip_address: option.Some("10.0.0.1"),
    nas_identifier: option.Some("edge-a"),
    active_profile_id: option.Some("svc_home_100m"),
    attributes: [
      vendor_types.RadiusAttribute(name: "class", value: "normal"),
    ],
    last_accounting_epoch_seconds: 1_710_000_000,
    stop_epoch_seconds: option.None,
    status: types.AccountingInterimUpdate,
  )
}

fn sample_stop_record() -> types.AccountingRecord {
  types.AccountingRecord(
    tenant_id: "tenant_a",
    service_id: "svc_1",
    username: option.Some("cust_001"),
    acct_session_id: option.Some("sess-1"),
    framed_ip: option.Some("10.10.20.5"),
    nas_ip_address: option.Some("10.0.0.1"),
    nas_identifier: option.Some("edge-a"),
    active_profile_id: option.Some("svc_home_100m"),
    attributes: [
      vendor_types.RadiusAttribute(name: "class", value: "normal"),
    ],
    last_accounting_epoch_seconds: 1_710_000_100,
    stop_epoch_seconds: option.Some(1_710_000_100),
    status: types.AccountingStop,
  )
}

fn sample_active_session() -> types.ActiveSession {
  types.ActiveSession(
    tenant_id: "tenant_a",
    service_id: "svc_1",
    username: option.Some("cust_001"),
    acct_session_id: option.Some("sess-1"),
    framed_ip: option.Some("10.10.20.5"),
    nas_ip_address: option.Some("10.0.0.1"),
    nas_identifier: option.Some("edge-a"),
    active_profile_id: option.Some("svc_home_100m"),
    attributes: [
      vendor_types.RadiusAttribute(name: "class", value: "normal"),
    ],
    last_accounting_epoch_seconds: 1_710_000_000,
    session_active: True,
  )
}
