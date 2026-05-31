import gleam/option
import oxion/radius/accounting/materializer
import oxion/radius/accounting/radacct
import oxion/radius/api/policy_runtime
import oxion/radius/api/rlm_rest_request
import oxion/radius/api/rlm_rest_response
import oxion/radius/session/types as session_types

pub fn compact_authorize_allows_valid_password_request_test() {
  let body =
    "{\"username\":\"testing\",\"password_present\":\"testing123\",\"nas_ip_address\":\"127.0.1.1\",\"nas_port\":\"0\",\"acct_session_id\":\"sess-1\"}"

  let assert Ok(request) = rlm_rest_request.parse_authorize(body)
  assert request.username == "testing"
  assert request.user_password_present == True
  assert policy_runtime.authorize(request)
    == policy_runtime.Allow(reply_message: "oxRADIUS callback accepted")
}

pub fn native_authorize_extracts_freeradius_attribute_map_test() {
  let body =
    "{\"User-Name\":{\"type\":\"string\",\"value\":[\"testing\"]},\"User-Password\":{\"type\":\"string\",\"value\":[\"testing123\"]},\"NAS-IP-Address\":{\"type\":\"ipaddr\",\"value\":[\"127.0.1.1\"]}}"

  let assert Ok(request) = rlm_rest_request.parse_authorize(body)
  assert request.username == "testing"
  assert request.user_password_present == True
  assert request.nas_ip_address == option.Some("127.0.1.1")
}

pub fn policy_runtime_denies_missing_password_test() {
  let body = "{\"username\":\"unknown\"}"
  let assert Ok(request) = rlm_rest_request.parse_authorize(body)

  assert policy_runtime.authorize(request)
    == policy_runtime.Deny(reply_message: "oxRADIUS callback rejected")
}

pub fn authorize_response_renders_rlm_rest_attribute_json_test() {
  let body =
    rlm_rest_response.authorize_body(policy_runtime.Allow(
      "oxRADIUS callback accepted",
    ))

  assert body
    == "{\"Reply-Message\":{\"op\":\":=\",\"value\":[\"oxRADIUS callback accepted\"]}}"
}

pub fn compact_accounting_maps_to_radacct_and_active_session_test() {
  let body =
    "{\"username\":\"testing\",\"acct_status_type\":\"Start\",\"acct_session_id\":\"sess-1\",\"framed_ip_address\":\"10.0.0.10\",\"nas_ip_address\":\"127.0.1.1\",\"event_epoch_seconds\":\"1710000000\"}"

  let assert Ok(request) = rlm_rest_request.parse_accounting(body)
  let write = radacct.from_accounting_request(request)
  assert write.acct_status_type == "Start"
  assert write.acct_session_id == option.Some("sess-1")

  let record = materializer.to_accounting_record(request)
  assert record.status == session_types.AccountingStart
  assert record.last_accounting_epoch_seconds == 1_710_000_000

  let assert Ok(session) = materializer.to_active_session(request)
  assert session.session_active == True
  assert session.username == option.Some("testing")
}

pub fn native_accounting_maps_stop_to_inactive_record_test() {
  let body =
    "{\"User-Name\":{\"type\":\"string\",\"value\":[\"testing\"]},\"Acct-Status-Type\":{\"type\":\"integer\",\"value\":[\"Stop\"]},\"Acct-Session-Id\":{\"type\":\"string\",\"value\":[\"sess-1\"]},\"Event-Timestamp\":{\"type\":\"date\",\"value\":[\"1710000100\"]}}"

  let assert Ok(request) = rlm_rest_request.parse_accounting(body)
  let record = materializer.to_accounting_record(request)
  assert record.status == session_types.AccountingStop
  assert record.stop_epoch_seconds == option.Some(1_710_000_100)
  assert materializer.to_active_session(request)
    == Error(session_types.InactiveAccountingRecord)
}
