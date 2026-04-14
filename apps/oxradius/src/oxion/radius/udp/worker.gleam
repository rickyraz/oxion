import gleam/int
import gleam/list
import gleam/option
import oxion/radius/udp/types

pub type WorkerError {
  InflightLimitExceeded
  DuplicateIdentifier(endpoint_id: String, identifier: Int)
  SocketOpenFailed(reason: String)
}

pub type WorkerState {
  WorkerState(
    config: types.UdpWorkerConfig,
    inflight: List(types.OutstandingRequest),
    socket_handle: option.Option(types.SocketHandle),
  )
}

@external(erlang, "oxion_radius_transport_ffi", "open_reusable_udp_socket")
fn open_reusable_udp_socket(
  local_bind: String,
  reuse_socket: Bool,
) -> Result(Int, String)

@external(erlang, "oxion_radius_transport_ffi", "send_and_receive_with_socket")
fn send_and_receive_with_socket(
  handle: Int,
  host: String,
  port: Int,
  payload: BitArray,
  timeout_ms: Int,
) -> Result(BitArray, String)

@external(erlang, "oxion_radius_transport_ffi", "send_and_receive")
fn send_and_receive(
  host: String,
  port: Int,
  payload: BitArray,
  timeout_ms: Int,
) -> Result(BitArray, String)

@external(erlang, "oxion_radius_transport_ffi", "close_reusable_udp_socket")
fn close_reusable_udp_socket(handle: Int) -> Nil

pub fn init(config: types.UdpWorkerConfig) -> WorkerState {
  WorkerState(config: config, inflight: [], socket_handle: option.None)
}

pub fn register(
  state: WorkerState,
  request: types.OutstandingRequest,
) -> Result(WorkerState, WorkerError) {
  let types.OutstandingRequest(
    endpoint_id: _endpoint_id,
    identifier: _identifier,
    started_at_ms: started_at_ms,
    timeout_ms: _timeout_ms,
  ) = request

  register_at(state, request, started_at_ms)
}

pub fn register_at(
  state: WorkerState,
  request: types.OutstandingRequest,
  now_ms: Int,
) -> Result(WorkerState, WorkerError) {
  let pruned_state = prune_timed_out(state, now_ms)
  let WorkerState(
    config: config,
    inflight: inflight,
    socket_handle: socket_handle,
  ) = pruned_state
  let types.UdpWorkerConfig(
    local_bind: _local_bind,
    max_inflight: max_inflight,
    reuse_socket: _reuse_socket,
  ) = config
  let types.OutstandingRequest(
    endpoint_id: request_endpoint_id,
    identifier: request_identifier,
    started_at_ms: _started_at_ms,
    timeout_ms: _timeout_ms,
  ) = request

  case list.length(inflight) >= max_inflight {
    True -> Error(InflightLimitExceeded)
    False ->
      case
        list.any(inflight, fn(candidate) {
          let types.OutstandingRequest(
            endpoint_id: candidate_endpoint_id,
            identifier: candidate_identifier,
            started_at_ms: _candidate_started_at_ms,
            timeout_ms: _candidate_timeout_ms,
          ) = candidate

          candidate_endpoint_id == request_endpoint_id
          && candidate_identifier == request_identifier
        })
      {
        True ->
          Error(DuplicateIdentifier(
            endpoint_id: request_endpoint_id,
            identifier: request_identifier,
          ))
        False ->
          Ok(WorkerState(
            config: config,
            inflight: [request, ..inflight],
            socket_handle: socket_handle,
          ))
      }
  }
}

pub fn acknowledge(
  state: WorkerState,
  endpoint_id: String,
  identifier: Int,
) -> WorkerState {
  let WorkerState(
    config: config,
    inflight: inflight,
    socket_handle: socket_handle,
  ) = state

  WorkerState(
    config: config,
    inflight: list.filter(inflight, fn(candidate) {
      let types.OutstandingRequest(
        endpoint_id: candidate_endpoint_id,
        identifier: candidate_identifier,
        started_at_ms: _started_at_ms,
        timeout_ms: _timeout_ms,
      ) = candidate

      candidate_endpoint_id != endpoint_id || candidate_identifier != identifier
    }),
    socket_handle: socket_handle,
  )
}

pub fn prune_timed_out(state: WorkerState, now_ms: Int) -> WorkerState {
  let WorkerState(
    config: config,
    inflight: inflight,
    socket_handle: socket_handle,
  ) = state

  WorkerState(
    config: config,
    inflight: list.filter(inflight, fn(candidate) {
      let types.OutstandingRequest(
        endpoint_id: _endpoint_id,
        identifier: _identifier,
        started_at_ms: started_at_ms,
        timeout_ms: timeout_ms,
      ) = candidate

      now_ms - started_at_ms < timeout_ms
    }),
    socket_handle: socket_handle,
  )
}

pub fn snapshot(state: WorkerState) -> types.UdpWorkerSnapshot {
  let WorkerState(
    config: config,
    inflight: inflight,
    socket_handle: socket_handle,
  ) = state
  let types.UdpWorkerConfig(
    local_bind: _local_bind,
    max_inflight: _max_inflight,
    reuse_socket: reuse_socket,
  ) = config

  types.UdpWorkerSnapshot(
    inflight_count: list.length(inflight),
    socket_handle: socket_handle,
    reuse_socket: reuse_socket,
  )
}

pub fn close(state: WorkerState) -> WorkerState {
  let WorkerState(
    config: config,
    inflight: inflight,
    socket_handle: socket_handle,
  ) = state

  case socket_handle {
    option.Some(types.SocketHandle(value: handle)) -> {
      close_reusable_udp_socket(handle)
      WorkerState(
        config: config,
        inflight: inflight,
        socket_handle: option.None,
      )
    }
    option.None -> state
  }
}

// Why: the worker owns socket lifecycle and inflight bookkeeping so transport
// modules can share one UDP socket without reimplementing identifier tracking.
pub fn roundtrip(
  state: WorkerState,
  request: types.OutstandingRequest,
  host: String,
  port: Int,
  payload: BitArray,
  now_ms: Int,
) -> #(Result(BitArray, String), WorkerState) {
  let prepared_state = prune_timed_out(state, now_ms)

  case ensure_socket(prepared_state) {
    Error(error) -> #(Error(error_reason(error)), prepared_state)
    Ok(socket_ready_state) ->
      case register_at(socket_ready_state, request, now_ms) {
        Error(error) -> #(Error(error_reason(error)), socket_ready_state)
        Ok(registered_state) -> {
          let types.OutstandingRequest(
            endpoint_id: endpoint_id,
            identifier: identifier,
            started_at_ms: _started_at_ms,
            timeout_ms: timeout_ms,
          ) = request
          let result =
            dispatch(registered_state, host, port, payload, timeout_ms)

          #(result, acknowledge(registered_state, endpoint_id, identifier))
        }
      }
  }
}

fn ensure_socket(state: WorkerState) -> Result(WorkerState, WorkerError) {
  let WorkerState(
    config: config,
    inflight: inflight,
    socket_handle: socket_handle,
  ) = state
  let types.UdpWorkerConfig(
    local_bind: local_bind,
    max_inflight: _max_inflight,
    reuse_socket: reuse_socket,
  ) = config

  case reuse_socket, socket_handle {
    False, _ -> Ok(state)
    True, option.Some(_) -> Ok(state)
    True, option.None ->
      case open_reusable_udp_socket(local_bind, reuse_socket) {
        Ok(handle) ->
          Ok(WorkerState(
            config: config,
            inflight: inflight,
            socket_handle: option.Some(types.SocketHandle(value: handle)),
          ))
        Error(reason) -> Error(SocketOpenFailed(reason: reason))
      }
  }
}

fn dispatch(
  state: WorkerState,
  host: String,
  port: Int,
  payload: BitArray,
  timeout_ms: Int,
) -> Result(BitArray, String) {
  let WorkerState(
    config: config,
    inflight: _inflight,
    socket_handle: socket_handle,
  ) = state
  let types.UdpWorkerConfig(
    local_bind: _local_bind,
    max_inflight: _max_inflight,
    reuse_socket: reuse_socket,
  ) = config

  case reuse_socket, socket_handle {
    True, option.Some(types.SocketHandle(value: handle)) ->
      send_and_receive_with_socket(handle, host, port, payload, timeout_ms)
    _, _ -> send_and_receive(host, port, payload, timeout_ms)
  }
}

fn error_reason(error: WorkerError) -> String {
  case error {
    InflightLimitExceeded -> "inflight_limit_exceeded"
    DuplicateIdentifier(endpoint_id, identifier) ->
      "duplicate_identifier:" <> endpoint_id <> ":" <> int.to_string(identifier)
    SocketOpenFailed(reason) -> "socket_open_failed:" <> reason
  }
}
