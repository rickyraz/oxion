import gleam/int
import gleam/option

pub type DisconnectExecutionResult {
  ReplayRejected(reason: String)
  Ack(retries: Int)
  Nak(code: String, message: String, retries: Int)
  Timeout(retries: Int)
  BuildRejected(reason: String)
  SnapshotUnavailable(reason: String)
  TransportFailed(reason: String, retries: Int)
}

pub fn retry_count(result: DisconnectExecutionResult) -> Int {
  case result {
    ReplayRejected(_) -> 0
    Ack(retries) -> retries
    Nak(_, _, retries) -> retries
    Timeout(retries) -> retries
    BuildRejected(_) -> 0
    SnapshotUnavailable(_) -> 0
    TransportFailed(_, retries) -> retries
  }
}

pub fn reason(result: DisconnectExecutionResult) -> option.Option(String) {
  case result {
    ReplayRejected(reason) -> option.Some(reason)
    Ack(_) -> option.None
    Nak(code, message, _) -> option.Some(code <> ":" <> message)
    Timeout(retries) ->
      option.Some("timeout_after_retries:" <> int.to_string(retries))
    BuildRejected(reason) -> option.Some(reason)
    SnapshotUnavailable(reason) -> option.Some(reason)
    TransportFailed(reason, _) -> option.Some(reason)
  }
}
