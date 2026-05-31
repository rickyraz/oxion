import gleam/option
import oxion/radius/api/rlm_rest_request
import oxion/radius/session/types as session_types

pub type RadacctWrite {
  RadacctWrite(
    username: option.Option(String),
    acct_session_id: option.Option(String),
    acct_status_type: String,
    framed_ip_address: option.Option(String),
    nas_ip_address: option.Option(String),
    nas_identifier: option.Option(String),
    active_profile_id: option.Option(String),
    event_epoch_seconds: Int,
  )
}

pub fn from_accounting_request(
  request: rlm_rest_request.AccountingRequest,
) -> RadacctWrite {
  let rlm_rest_request.AccountingRequest(
    username: username,
    acct_status_type: status,
    acct_session_id: acct_session_id,
    framed_ip: framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
    active_profile_id: active_profile_id,
    event_epoch_seconds: event_epoch_seconds,
    ..,
  ) = request

  RadacctWrite(
    username: username,
    acct_session_id: acct_session_id,
    acct_status_type: status_to_string(status),
    framed_ip_address: framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
    active_profile_id: active_profile_id,
    event_epoch_seconds: event_epoch_seconds,
  )
}

fn status_to_string(status: session_types.AccountingStatus) -> String {
  case status {
    session_types.AccountingStart -> "Start"
    session_types.AccountingInterimUpdate -> "Interim-Update"
    session_types.AccountingStop -> "Stop"
  }
}
