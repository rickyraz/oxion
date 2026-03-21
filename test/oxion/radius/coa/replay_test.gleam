import oxion/radius/coa/replay

pub fn replay_accepts_new_fresh_request_test() {
  let cache = replay.new()
  let entry =
    replay.ReplayEntry(
      endpoint_id: "edge_1",
      identifier: 7,
      request_authenticator: <<1, 2, 3, 4>>,
      event_timestamp: 100,
    )

  case
    replay.validate_and_store(
      cache,
      entry,
      replay.ReplayWindow(max_age_seconds: 30, max_entries: 10),
      110,
    )
  {
    Ok(next_cache) -> {
      assert replay.contains(next_cache, entry)
    }
    Error(_) -> panic
  }
}

pub fn replay_rejects_duplicate_request_test() {
  let entry =
    replay.ReplayEntry(
      endpoint_id: "edge_1",
      identifier: 7,
      request_authenticator: <<1, 2, 3, 4>>,
      event_timestamp: 100,
    )
  let cache = case
    replay.validate_and_store(
      replay.new(),
      entry,
      replay.ReplayWindow(max_age_seconds: 30, max_entries: 10),
      110,
    )
  {
    Ok(cache) -> cache
    Error(_) -> panic
  }

  assert replay.validate_and_store(
      cache,
      entry,
      replay.ReplayWindow(max_age_seconds: 30, max_entries: 10),
      110,
    )
    == Error(replay.DuplicateRequest)
}
