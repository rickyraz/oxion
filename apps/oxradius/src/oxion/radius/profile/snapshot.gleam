import gleam/option
import oxion/radius/vendor/types as vendor_types

pub type SessionSelector {
  SessionSelector(
    username: option.Option(String),
    framed_ip: option.Option(String),
    acct_session_id: option.Option(String),
    nas_ip_address: option.Option(String),
  )
}

pub type ActiveProfileSnapshot {
  ActiveProfileSnapshot(
    service_id: String,
    selector: SessionSelector,
    profile_id: option.Option(String),
    attributes: List(vendor_types.RadiusAttribute),
    session_active: Bool,
  )
}

pub type SnapshotError {
  MissingSessionSelector
}

pub fn validate_selector(
  selector: SessionSelector,
) -> Result(Nil, SnapshotError) {
  let SessionSelector(
    username: username,
    framed_ip: framed_ip,
    acct_session_id: acct_session_id,
    nas_ip_address: nas_ip_address,
  ) = selector

  case
    has_value(username)
    || has_value(framed_ip)
    || has_value(acct_session_id)
    || has_value(nas_ip_address)
  {
    True -> Ok(Nil)
    False -> Error(MissingSessionSelector)
  }
}

fn has_value(value: option.Option(String)) -> Bool {
  case value {
    option.Some(item) -> item != ""
    option.None -> False
  }
}
