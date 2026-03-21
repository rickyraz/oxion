import gleam/int
import gleam/list

pub type RetryError(error) {
  InvalidMaxAttempts
  NoAttemptsProvided
  AttemptsExceeded(last_error: error)
}

/// Builds a stable fingerprint per tenant/subscriber/invoice/stage/action instance.
pub fn action_fingerprint(
  tenant_id: String,
  subscriber_id: String,
  invoice_id: String,
  stage_id: String,
  action_position: Int,
  action_identity: String,
) -> String {
  tenant_id
  <> ":"
  <> subscriber_id
  <> ":"
  <> invoice_id
  <> ":"
  <> stage_id
  <> ":"
  <> int.to_string(action_position)
  <> ":"
  <> action_identity
}

/// Returns `True` when a fingerprint has not been processed before.
pub fn should_execute(
  existing_fingerprints: List(String),
  fingerprint: String,
) -> Bool {
  list.contains(existing_fingerprints, fingerprint) == False
}

/// Adds fingerprint only if it is new.
pub fn append_fingerprint(
  existing_fingerprints: List(String),
  fingerprint: String,
) -> List(String) {
  case should_execute(existing_fingerprints, fingerprint) {
    True -> [fingerprint, ..existing_fingerprints]
    False -> existing_fingerprints
  }
}

/// Executes retry attempts from prepared results with a strict max-attempt limit.
pub fn execute_with_retry_from_attempts(
  attempts: List(Result(value, error)),
  max_attempts: Int,
) -> Result(value, RetryError(error)) {
  case max_attempts > 0 {
    False -> Error(InvalidMaxAttempts)
    True ->
      case attempts {
        [] -> Error(NoAttemptsProvided)
        _ -> execute_retry_loop(attempts, max_attempts, 0)
      }
  }
}

// Consumes retry attempts recursively until success or terminal failure.
fn execute_retry_loop(
  attempts: List(Result(value, error)),
  max_attempts: Int,
  current_attempt: Int,
) -> Result(value, RetryError(error)) {
  case attempts {
    [] -> Error(NoAttemptsProvided)
    [attempt, ..rest] ->
      case attempt {
        Ok(value) -> Ok(value)
        Error(reason) ->
          case current_attempt + 1 >= max_attempts {
            True -> Error(AttemptsExceeded(last_error: reason))
            False ->
              case rest {
                [] -> Error(AttemptsExceeded(last_error: reason))
                _ -> execute_retry_loop(rest, max_attempts, current_attempt + 1)
              }
          }
      }
  }
}
