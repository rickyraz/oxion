import gleam/option
import gleeunit
import oxion/radius/coa/result as coa_result
import oxion/radius/disconnect/result as disconnect_result

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn coa_result_reason_test() {
  assert coa_result.reason(coa_result.IdempotentSkip("already_applied"))
    == option.Some("already_applied")
}

pub fn coa_result_retry_count_contract_test() {
  assert coa_result.retry_count(coa_result.IdempotentSkip("already_applied"))
    == 0
  assert coa_result.retry_count(coa_result.ReplayRejected("duplicate_request"))
    == 0
  assert coa_result.retry_count(coa_result.Ack("bw_4mbps", 2)) == 2
  assert coa_result.retry_count(coa_result.Nak("506", "Request-Invalid", 1))
    == 1
  assert coa_result.retry_count(coa_result.Timeout(3)) == 3
  assert coa_result.retry_count(coa_result.SnapshotUnavailable("missing")) == 0
  assert coa_result.retry_count(coa_result.ProfileResolutionFailed(
      "unknown_profile",
    ))
    == 0
  assert coa_result.retry_count(coa_result.BuildRejected("invalid_selector"))
    == 0
  assert coa_result.retry_count(coa_result.InvalidRetryPolicy(
      "max_attempts_zero",
    ))
    == 0
  assert coa_result.retry_count(coa_result.TransportFailed("socket_down", 4))
    == 4
}

pub fn coa_result_reason_contract_test() {
  assert coa_result.reason(coa_result.IdempotentSkip("already_applied"))
    == option.Some("already_applied")
  assert coa_result.reason(coa_result.ReplayRejected("duplicate_request"))
    == option.Some("duplicate_request")
  assert coa_result.reason(coa_result.Ack("bw_4mbps", 2)) == option.None
  assert coa_result.reason(coa_result.Nak("506", "Request-Invalid", 1))
    == option.Some("506:Request-Invalid")
  assert coa_result.reason(coa_result.Timeout(3))
    == option.Some("timeout_after_retries:3")
  assert coa_result.reason(coa_result.SnapshotUnavailable("missing_snapshot"))
    == option.Some("missing_snapshot")
  assert coa_result.reason(coa_result.ProfileResolutionFailed("unknown_profile"))
    == option.Some("unknown_profile")
  assert coa_result.reason(coa_result.BuildRejected("invalid_selector"))
    == option.Some("invalid_selector")
  assert coa_result.reason(coa_result.InvalidRetryPolicy("max_attempts_zero"))
    == option.Some("max_attempts_zero")
  assert coa_result.reason(coa_result.TransportFailed("socket_down", 4))
    == option.Some("socket_down")
}

pub fn disconnect_result_retry_count_contract_test() {
  assert disconnect_result.retry_count(disconnect_result.ReplayRejected(
      "duplicate_request",
    ))
    == 0
  assert disconnect_result.retry_count(disconnect_result.Ack(retries: 1)) == 1
  assert disconnect_result.retry_count(disconnect_result.Nak(
      "503",
      "session context missing",
      2,
    ))
    == 2
  assert disconnect_result.retry_count(disconnect_result.Timeout(3)) == 3
  assert disconnect_result.retry_count(disconnect_result.BuildRejected(
      "unsupported_disconnect_command",
    ))
    == 0
  assert disconnect_result.retry_count(disconnect_result.SnapshotUnavailable(
      "no_active_session",
    ))
    == 0
  assert disconnect_result.retry_count(disconnect_result.TransportFailed(
      "socket_down",
      4,
    ))
    == 4
}

pub fn disconnect_result_reason_contract_test() {
  assert disconnect_result.reason(disconnect_result.ReplayRejected(
      "duplicate_request",
    ))
    == option.Some("duplicate_request")
  assert disconnect_result.reason(disconnect_result.Ack(retries: 1))
    == option.None
  assert disconnect_result.reason(disconnect_result.Nak(
      "503",
      "session context missing",
      2,
    ))
    == option.Some("503:session context missing")
  assert disconnect_result.reason(disconnect_result.Timeout(3))
    == option.Some("timeout_after_retries:3")
  assert disconnect_result.reason(disconnect_result.BuildRejected(
      "unsupported_disconnect_command",
    ))
    == option.Some("unsupported_disconnect_command")
  assert disconnect_result.reason(disconnect_result.SnapshotUnavailable(
      "no_active_session",
    ))
    == option.Some("no_active_session")
  assert disconnect_result.reason(disconnect_result.TransportFailed(
      "socket_down",
      4,
    ))
    == option.Some("socket_down")
}
