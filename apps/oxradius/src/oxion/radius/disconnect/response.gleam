pub type DisconnectResponse {
  Ack(nas: String)
  Nak(nas: String, error_code: String, error_message: String)
  Timeout
  TransportError(reason: String)
  Malformed(reason: String)
}
