import gleam/list
import gleam/option
import oxion/radius/profile/snapshot
import oxion/radius/session/types

pub fn to_snapshot(
  session: types.ActiveSession,
) -> snapshot.ActiveProfileSnapshot {
  let types.ActiveSession(
    tenant_id: _tenant_id,
    service_id: service_id,
    username: username,
    acct_session_id: acct_session_id,
    framed_ip: framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: _nas_identifier,
    active_profile_id: active_profile_id,
    attributes: attributes,
    last_accounting_epoch_seconds: _last_accounting_epoch_seconds,
    session_active: session_active,
  ) = session

  snapshot.ActiveProfileSnapshot(
    service_id: service_id,
    selector: snapshot.SessionSelector(
      username: username,
      framed_ip: framed_ip,
      acct_session_id: acct_session_id,
      nas_ip_address: nas_ip_address,
    ),
    profile_id: active_profile_id,
    attributes: attributes,
    session_active: session_active,
  )
}

// Why: session targeting must become a real read-model concern rather than a
// caller-supplied guess, so the resolver needs deterministic matching rules.
pub fn resolve_active_session(
  sessions: List(types.ActiveSession),
  lookup: types.SessionLookup,
  max_age_seconds: Int,
  now_seconds: Int,
) -> Result(types.ActiveSession, types.SessionResolutionError) {
  case list.filter(sessions, fn(session) { matches_lookup(session, lookup) }) {
    [] -> Error(types.NoActiveSession)
    [session] -> validate_freshness(session, max_age_seconds, now_seconds)
    _ -> Error(types.AmbiguousSession)
  }
}

fn matches_lookup(
  session: types.ActiveSession,
  lookup: types.SessionLookup,
) -> Bool {
  let types.ActiveSession(
    tenant_id: session_tenant_id,
    service_id: session_service_id,
    username: session_username,
    acct_session_id: session_acct_session_id,
    framed_ip: session_framed_ip,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    active_profile_id: _active_profile_id,
    attributes: _attributes,
    last_accounting_epoch_seconds: _last_accounting_epoch_seconds,
    session_active: session_active,
  ) = session
  let types.SessionLookup(
    tenant_id: lookup_tenant_id,
    service_id: lookup_service_id,
    username: lookup_username,
    acct_session_id: lookup_acct_session_id,
    framed_ip: lookup_framed_ip,
  ) = lookup

  session_active
  && session_tenant_id == lookup_tenant_id
  && session_service_id == lookup_service_id
  && option_matches(lookup_username, session_username)
  && option_matches(lookup_acct_session_id, session_acct_session_id)
  && option_matches(lookup_framed_ip, session_framed_ip)
}

fn option_matches(
  expected: option.Option(String),
  actual: option.Option(String),
) -> Bool {
  case expected {
    option.None -> True
    option.Some(expected_value) ->
      case actual {
        option.Some(actual_value) -> expected_value == actual_value
        option.None -> False
      }
  }
}

fn validate_freshness(
  session: types.ActiveSession,
  max_age_seconds: Int,
  now_seconds: Int,
) -> Result(types.ActiveSession, types.SessionResolutionError) {
  let types.ActiveSession(
    tenant_id: _tenant_id,
    service_id: _service_id,
    username: _username,
    acct_session_id: _acct_session_id,
    framed_ip: _framed_ip,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    active_profile_id: _active_profile_id,
    attributes: _attributes,
    last_accounting_epoch_seconds: last_accounting_epoch_seconds,
    session_active: _session_active,
  ) = session

  case
    max_age_seconds > 0
    && now_seconds - last_accounting_epoch_seconds <= max_age_seconds
  {
    True -> Ok(session)
    False -> Error(types.StaleSession(max_age_seconds: max_age_seconds))
  }
}
