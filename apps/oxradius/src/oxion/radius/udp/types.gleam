import gleam/option

pub type UdpWorkerConfig {
  UdpWorkerConfig(local_bind: String, max_inflight: Int, reuse_socket: Bool)
}

pub type OutstandingRequest {
  OutstandingRequest(
    endpoint_id: String,
    identifier: Int,
    started_at_ms: Int,
    timeout_ms: Int,
  )
}

pub type SocketHandle {
  SocketHandle(value: Int)
}

pub type UdpWorkerSnapshot {
  UdpWorkerSnapshot(
    inflight_count: Int,
    socket_handle: option.Option(SocketHandle),
    reuse_socket: Bool,
  )
}
