import gleam/list
import gleam/option
import oxion/radius/session/types

pub type FreeRadiusSchemaVersion {
  FreeRadiusV1
  FreeRadiusV2
  FreeRadiusV3
  UnknownVersion(value: String)
}

pub type PostAuthColumns {
  PostAuthColumns(user_field: String, date_field: String)
}

pub fn from_string(value: String) -> FreeRadiusSchemaVersion {
  case value {
    "1" -> FreeRadiusV1
    "2" -> FreeRadiusV2
    "3" -> FreeRadiusV3
    _ -> UnknownVersion(value: value)
  }
}

pub fn postauth_columns(version: FreeRadiusSchemaVersion) -> PostAuthColumns {
  case version {
    FreeRadiusV1 -> PostAuthColumns(user_field: "user", date_field: "date")
    FreeRadiusV2 | FreeRadiusV3 | UnknownVersion(_) ->
      PostAuthColumns(user_field: "username", date_field: "authdate")
  }
}

pub fn materialize_active_sessions(
  records: List(types.AccountingRecord),
) -> List(types.ActiveSession) {
  list.fold(records, [], fn(sessions, record) {
    case from_accounting_record(record) {
      Ok(session) -> [session, ..sessions]
      Error(_) -> sessions
    }
  })
  |> list.reverse
}

// Why: the session read model must be derived from accounting-style runtime
// facts rather than hand-assembled snapshots, or the managed CoA path keeps
// lying about what session state is authoritative.
pub fn from_accounting_record(
  record: types.AccountingRecord,
) -> Result(types.ActiveSession, types.SessionMaterializationError) {
  let types.AccountingRecord(
    tenant_id: tenant_id,
    service_id: service_id,
    username: username,
    acct_session_id: acct_session_id,
    framed_ip: framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
    active_profile_id: active_profile_id,
    attributes: attributes,
    last_accounting_epoch_seconds: last_accounting_epoch_seconds,
    stop_epoch_seconds: stop_epoch_seconds,
    status: status,
  ) = record

  case is_active_record(status, stop_epoch_seconds) {
    False -> Error(types.InactiveAccountingRecord)
    True ->
      case has_identity(username, acct_session_id, framed_ip) {
        False -> Error(types.MissingAccountingIdentity)
        True ->
          Ok(types.ActiveSession(
            tenant_id: tenant_id,
            service_id: service_id,
            username: username,
            acct_session_id: acct_session_id,
            framed_ip: framed_ip,
            nas_ip_address: nas_ip_address,
            nas_identifier: nas_identifier,
            active_profile_id: active_profile_id,
            attributes: attributes,
            last_accounting_epoch_seconds: last_accounting_epoch_seconds,
            session_active: True,
          ))
      }
  }
}

fn is_active_record(
  status: types.AccountingStatus,
  stop_epoch_seconds: option.Option(Int),
) -> Bool {
  case status {
    types.AccountingStop -> False
    types.AccountingStart | types.AccountingInterimUpdate ->
      case stop_epoch_seconds {
        option.None -> True
        option.Some(_) -> False
      }
  }
}

fn has_identity(
  username: option.Option(String),
  acct_session_id: option.Option(String),
  framed_ip: option.Option(String),
) -> Bool {
  case username {
    option.Some(_) -> True
    option.None ->
      case acct_session_id {
        option.Some(_) -> True
        option.None ->
          case framed_ip {
            option.Some(_) -> True
            option.None -> False
          }
      }
  }
}
