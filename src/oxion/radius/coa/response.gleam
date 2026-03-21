pub type CoaResponse {
  Ack(nas: String, applied_target: String)
  Nak(nas: String, error_code: String, error_message: String)
  Timeout
  TransportError(reason: String)
  Malformed(reason: String)
}
