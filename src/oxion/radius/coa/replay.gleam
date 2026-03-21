import gleam/bit_array
import gleam/list

pub type ReplayWindow {
  ReplayWindow(max_age_seconds: Int, max_entries: Int)
}

pub type ReplayEntry {
  ReplayEntry(
    endpoint_id: String,
    identifier: Int,
    request_authenticator: BitArray,
    event_timestamp: Int,
  )
}

pub type ReplayCache {
  ReplayCache(entries: List(ReplayEntry))
}

pub type ReplayError {
  InvalidReplayWindow
  MissingEventTimestamp
  StaleEventTimestamp
  DuplicateRequest
}

pub fn new() -> ReplayCache {
  ReplayCache(entries: [])
}

// Why: replay validation must be pure and deterministic first so the packet
// path can adopt it without hiding stateful security decisions in the transport.
pub fn validate_and_store(
  cache: ReplayCache,
  entry: ReplayEntry,
  window: ReplayWindow,
  now_seconds: Int,
) -> Result(ReplayCache, ReplayError) {
  let ReplayWindow(max_age_seconds: max_age_seconds, max_entries: max_entries) =
    window
  let ReplayEntry(
    endpoint_id: _endpoint_id,
    identifier: _identifier,
    request_authenticator: _request_authenticator,
    event_timestamp: event_timestamp,
  ) = entry

  case max_age_seconds > 0 && max_entries > 0 {
    False -> Error(InvalidReplayWindow)
    True ->
      case event_timestamp <= 0 {
        True -> Error(MissingEventTimestamp)
        False ->
          case now_seconds - event_timestamp > max_age_seconds {
            True -> Error(StaleEventTimestamp)
            False -> {
              let ReplayCache(entries: entries) = cache
              let fresh_entries =
                prune_stale(entries, max_age_seconds, now_seconds)

              case contains_entry(fresh_entries, entry) {
                True -> Error(DuplicateRequest)
                False ->
                  Ok(
                    ReplayCache(entries: trim_to_limit(
                      [entry, ..fresh_entries],
                      max_entries,
                    )),
                  )
              }
            }
          }
      }
  }
}

pub fn contains(cache: ReplayCache, entry: ReplayEntry) -> Bool {
  let ReplayCache(entries: entries) = cache
  contains_entry(entries, entry)
}

fn contains_entry(entries: List(ReplayEntry), entry: ReplayEntry) -> Bool {
  list.any(entries, fn(candidate) { same_entry(candidate, entry) })
}

fn same_entry(left: ReplayEntry, right: ReplayEntry) -> Bool {
  let ReplayEntry(
    endpoint_id: left_endpoint_id,
    identifier: left_identifier,
    request_authenticator: left_request_authenticator,
    event_timestamp: left_event_timestamp,
  ) = left
  let ReplayEntry(
    endpoint_id: right_endpoint_id,
    identifier: right_identifier,
    request_authenticator: right_request_authenticator,
    event_timestamp: right_event_timestamp,
  ) = right

  left_endpoint_id == right_endpoint_id
  && left_identifier == right_identifier
  && left_event_timestamp == right_event_timestamp
  && bit_array.byte_size(left_request_authenticator)
  == bit_array.byte_size(right_request_authenticator)
  && left_request_authenticator == right_request_authenticator
}

fn prune_stale(
  entries: List(ReplayEntry),
  max_age_seconds: Int,
  now_seconds: Int,
) -> List(ReplayEntry) {
  list.filter(entries, fn(entry) {
    let ReplayEntry(
      endpoint_id: _endpoint_id,
      identifier: _identifier,
      request_authenticator: _request_authenticator,
      event_timestamp: event_timestamp,
    ) = entry

    now_seconds - event_timestamp <= max_age_seconds
  })
}

fn trim_to_limit(
  entries: List(ReplayEntry),
  max_entries: Int,
) -> List(ReplayEntry) {
  trim_to_limit_loop(entries, max_entries, [])
}

fn trim_to_limit_loop(
  remaining: List(ReplayEntry),
  slots_left: Int,
  acc: List(ReplayEntry),
) -> List(ReplayEntry) {
  case remaining, slots_left {
    _, limit if limit <= 0 -> list.reverse(acc)
    [], _ -> list.reverse(acc)
    [entry, ..rest], _ ->
      trim_to_limit_loop(rest, slots_left - 1, [entry, ..acc])
  }
}
