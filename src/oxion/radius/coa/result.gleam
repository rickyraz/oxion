import gleam/int
import gleam/option

pub type CoaExecutionResult {
  IdempotentSkip(reason: String)
  Ack(applied_target: String, retries: Int)
  Nak(code: String, message: String, retries: Int)
  Timeout(retries: Int)
  SnapshotUnavailable(reason: String)
  ProfileResolutionFailed(reason: String)
  BuildRejected(reason: String)
  InvalidRetryPolicy(reason: String)
  TransportFailed(reason: String, retries: Int)
}

pub fn retry_count(result: CoaExecutionResult) -> Int {
  case result {
    IdempotentSkip(_) -> 0
    Ack(_, retries) -> retries
    Nak(_, _, retries) -> retries
    Timeout(retries) -> retries
    SnapshotUnavailable(_) -> 0
    ProfileResolutionFailed(_) -> 0
    BuildRejected(_) -> 0
    InvalidRetryPolicy(_) -> 0
    TransportFailed(_, retries) -> retries
  }
}

pub fn reason(result: CoaExecutionResult) -> option.Option(String) {
  case result {
    IdempotentSkip(reason) -> option.Some(reason)
    Ack(_, _) -> option.None
    Nak(code, message, _) -> option.Some(code <> ":" <> message)
    Timeout(retries) ->
      option.Some("timeout_after_retries:" <> int.to_string(retries))
    SnapshotUnavailable(reason) -> option.Some(reason)
    ProfileResolutionFailed(reason) -> option.Some(reason)
    BuildRejected(reason) -> option.Some(reason)
    InvalidRetryPolicy(reason) -> option.Some(reason)
    TransportFailed(reason, _) -> option.Some(reason)
  }
}
