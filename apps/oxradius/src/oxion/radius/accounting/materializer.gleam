import gleam/option
import oxion/radius/api/rlm_rest_request
import oxion/radius/session/compatibility
import oxion/radius/session/types as session_types

pub fn to_accounting_record(
  request: rlm_rest_request.AccountingRequest,
) -> session_types.AccountingRecord {
  let rlm_rest_request.AccountingRequest(
    tenant_id: tenant_id,
    service_id: service_id,
    username: username,
    acct_status_type: status,
    acct_session_id: acct_session_id,
    framed_ip: framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
    active_profile_id: active_profile_id,
    event_epoch_seconds: event_epoch_seconds,
  ) = request

  session_types.AccountingRecord(
    tenant_id: tenant_id,
    service_id: service_id,
    username: username,
    acct_session_id: acct_session_id,
    framed_ip: framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
    active_profile_id: active_profile_id,
    attributes: [],
    last_accounting_epoch_seconds: event_epoch_seconds,
    stop_epoch_seconds: case status {
      session_types.AccountingStop -> option.Some(event_epoch_seconds)
      session_types.AccountingStart | session_types.AccountingInterimUpdate ->
        option.None
    },
    status: status,
  )
}

pub fn to_active_session(
  request: rlm_rest_request.AccountingRequest,
) -> Result(
  session_types.ActiveSession,
  session_types.SessionMaterializationError,
) {
  request
  |> to_accounting_record
  |> compatibility.from_accounting_record
}
