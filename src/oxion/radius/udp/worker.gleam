import gleam/list
import oxion/radius/udp/types

pub type WorkerError {
  InflightLimitExceeded
  DuplicateIdentifier(endpoint_id: String, identifier: Int)
}

pub type WorkerState {
  WorkerState(
    config: types.UdpWorkerConfig,
    inflight: List(types.OutstandingRequest),
  )
}

pub fn init(config: types.UdpWorkerConfig) -> WorkerState {
  WorkerState(config: config, inflight: [])
}

pub fn register(
  state: WorkerState,
  request: types.OutstandingRequest,
) -> Result(WorkerState, WorkerError) {
  let WorkerState(config: config, inflight: inflight) = state
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
          Ok(WorkerState(config: config, inflight: [request, ..inflight]))
      }
  }
}

pub fn acknowledge(
  state: WorkerState,
  endpoint_id: String,
  identifier: Int,
) -> WorkerState {
  let WorkerState(config: config, inflight: inflight) = state

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
  )
}
