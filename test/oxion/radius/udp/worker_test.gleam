import gleam/option
import oxion/radius/udp/types
import oxion/radius/udp/worker

@external(erlang, "oxion_radius_mock_transport_ffi", "start_echo_server")
fn start_echo_server() -> Result(Int, String)

pub fn udp_worker_register_prunes_timed_out_requests_test() {
  let state =
    worker.init(types.UdpWorkerConfig(
      local_bind: "0.0.0.0",
      max_inflight: 2,
      reuse_socket: True,
    ))
  let with_old_request = case
    worker.register(
      state,
      types.OutstandingRequest(
        endpoint_id: "edge_1",
        identifier: 7,
        started_at_ms: 100,
        timeout_ms: 50,
      ),
    )
  {
    Ok(state) -> state
    Error(_) -> panic
  }

  case
    worker.register_at(
      with_old_request,
      types.OutstandingRequest(
        endpoint_id: "edge_1",
        identifier: 7,
        started_at_ms: 220,
        timeout_ms: 50,
      ),
      220,
    )
  {
    Ok(next_state) -> {
      assert worker.snapshot(next_state)
        == types.UdpWorkerSnapshot(
          inflight_count: 1,
          socket_handle: option.None,
          reuse_socket: True,
        )
    }
    Error(_) -> panic
  }
}

pub fn udp_worker_roundtrip_reuses_socket_handle_test() {
  let first_port = case start_echo_server() {
    Ok(port) -> port
    Error(_) -> panic
  }
  let state =
    worker.init(types.UdpWorkerConfig(
      local_bind: "0.0.0.0",
      max_inflight: 4,
      reuse_socket: True,
    ))
  let #(first_result, state_after_first) =
    worker.roundtrip(
      state,
      types.OutstandingRequest(
        endpoint_id: "edge_1",
        identifier: 44,
        started_at_ms: 1_710_000_000,
        timeout_ms: 1000,
      ),
      "127.0.0.1",
      first_port,
      <<"ping">>,
      1_710_000_000,
    )

  case first_result {
    Ok(_response) -> Nil
    Error(_) -> panic
  }

  let types.UdpWorkerSnapshot(
    inflight_count: _first_inflight_count,
    socket_handle: first_socket_handle,
    reuse_socket: _first_reuse_socket,
  ) = worker.snapshot(state_after_first)
  let first_handle = case first_socket_handle {
    option.Some(handle) -> handle
    option.None -> panic
  }

  let second_port = case start_echo_server() {
    Ok(port) -> port
    Error(_) -> panic
  }
  let #(second_result, state_after_second) =
    worker.roundtrip(
      state_after_first,
      types.OutstandingRequest(
        endpoint_id: "edge_1",
        identifier: 45,
        started_at_ms: 1_710_000_100,
        timeout_ms: 1000,
      ),
      "127.0.0.1",
      second_port,
      <<"pong">>,
      1_710_000_100,
    )

  case second_result {
    Ok(_response) -> Nil
    Error(_) -> panic
  }

  assert worker.snapshot(state_after_second)
    == types.UdpWorkerSnapshot(
      inflight_count: 0,
      socket_handle: option.Some(first_handle),
      reuse_socket: True,
    )

  let _closed = worker.close(state_after_second)
  Nil
}
