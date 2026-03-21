import gleam/int
import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/replay
import oxion/radius/coa/retry
import oxion/radius/coa/transport as shared_transport
import oxion/radius/disconnect/request
import oxion/radius/disconnect/response
import oxion/radius/disconnect/result
import oxion/radius/disconnect/transport
import oxion/radius/registry/capability
import oxion/radius/registry/resolver as registry_resolver
import oxion/radius/registry/types
import oxion/radius/session/resolver as session_resolver
import oxion/radius/session/types as session_types
import oxion/radius/vendor/types as vendor_types

pub type DisconnectPreparationError {
  DisconnectUnsupportedByEndpoint(endpoint_id: String)
  UnsupportedTransport(kind: types.TransportKind)
}

pub type DisconnectPlan {
  DisconnectPlan(
    request: request.DisconnectRequest,
    endpoint: types.NasEndpoint,
  )
}

pub fn prepare(
  request_value: request.DisconnectRequest,
  endpoint: types.NasEndpoint,
) -> Result(DisconnectPlan, DisconnectPreparationError) {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: endpoint_id,
    vendor: _vendor,
    transport: transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: capabilities,
  ) = endpoint

  case capability.supports_disconnect(capabilities) {
    False -> Error(DisconnectUnsupportedByEndpoint(endpoint_id: endpoint_id))
    True ->
      case transport {
        types.Udp | types.RadSec ->
          Ok(DisconnectPlan(request: request_value, endpoint: endpoint))
      }
  }
}

pub fn send_disconnect_live(
  plan: DisconnectPlan,
  retry_policy: retry.RetryPolicy,
  transport_config: shared_transport.CoaTransportConfig,
) -> result.DisconnectExecutionResult {
  let DisconnectPlan(request: request_value, endpoint: _endpoint) = plan

  case retry.validate(retry_policy) {
    Error(retry.InvalidMaxAttempts) ->
      result.BuildRejected(reason: "invalid_max_attempts")
    Error(retry.EmptyBackoffSchedule) ->
      result.BuildRejected(reason: "empty_backoff_schedule")
    Ok(_) ->
      execute_live_attempts(request_value, transport_config, retry_policy, 0)
  }
}

pub fn send_disconnect_live_managed(
  plan: commands.CommandPlan,
  vendor: vendor_types.RadiusVendor,
  session_lookup: session_types.SessionLookup,
  session_max_age_seconds: Int,
  endpoints: List(types.NasEndpoint),
  sessions: List(session_types.ActiveSession),
  retry_policy: retry.RetryPolicy,
  now_seconds: Int,
) -> result.DisconnectExecutionResult {
  let session_types.SessionLookup(
    tenant_id: tenant_id,
    service_id: _service_id,
    username: _username,
    acct_session_id: _acct_session_id,
    framed_ip: _framed_ip,
  ) = session_lookup

  // Why: managed disconnect execution must resolve the same runtime session and
  // NAS state as CoA so disconnect enforcement does not bypass the source of
  // truth we established for active session targeting.
  case
    session_resolver.resolve_active_session(
      sessions,
      session_lookup,
      session_max_age_seconds,
      now_seconds,
    )
  {
    Error(error) ->
      result.SnapshotUnavailable(reason: session_error_reason(error))
    Ok(active_session) ->
      case
        request.build_request(
          plan,
          session_resolver.to_snapshot(active_session).selector,
        )
      {
        Error(error) -> result.BuildRejected(reason: build_error_reason(error))
        Ok(request_value) ->
          case
            registry_resolver.resolve_endpoint(
              endpoints,
              tenant_id,
              vendor,
              registry_resolver.from_active_session(active_session),
            )
          {
            Error(error) ->
              result.TransportFailed(
                reason: "endpoint_resolution_failed:"
                  <> registry_error_reason(error),
                retries: 0,
              )
            Ok(endpoint) ->
              case prepare(request_value, endpoint) {
                Error(error) ->
                  result.BuildRejected(reason: prepare_error_reason(error))
                Ok(disconnect_plan) ->
                  case endpoint_secret(endpoint) {
                    Error(reason) ->
                      result.TransportFailed(reason: reason, retries: 0)
                    Ok(secret) ->
                      send_disconnect_live(
                        disconnect_plan,
                        retry_policy,
                        shared_transport.from_endpoint(
                          endpoint,
                          secret,
                          now_seconds,
                        ),
                      )
                  }
              }
          }
      }
  }
}

pub fn send_disconnect_live_managed_with_replay(
  plan: commands.CommandPlan,
  vendor: vendor_types.RadiusVendor,
  session_lookup: session_types.SessionLookup,
  session_max_age_seconds: Int,
  endpoints: List(types.NasEndpoint),
  sessions: List(session_types.ActiveSession),
  retry_policy: retry.RetryPolicy,
  replay_cache: replay.ReplayCache,
  replay_window: replay.ReplayWindow,
  now_seconds: Int,
) -> #(result.DisconnectExecutionResult, replay.ReplayCache) {
  let session_types.SessionLookup(
    tenant_id: tenant_id,
    service_id: _service_id,
    username: _username,
    acct_session_id: _acct_session_id,
    framed_ip: _framed_ip,
  ) = session_lookup

  // Why: replay protection must apply to Disconnect with the same managed
  // boundary semantics as CoA, otherwise duplicate hard-suspend packets can
  // bypass the runtime guard simply by taking a different family path.
  case
    session_resolver.resolve_active_session(
      sessions,
      session_lookup,
      session_max_age_seconds,
      now_seconds,
    )
  {
    Error(error) -> #(
      result.SnapshotUnavailable(reason: session_error_reason(error)),
      replay_cache,
    )
    Ok(active_session) ->
      case
        request.build_request(
          plan,
          session_resolver.to_snapshot(active_session).selector,
        )
      {
        Error(error) -> #(
          result.BuildRejected(reason: build_error_reason(error)),
          replay_cache,
        )
        Ok(request_value) ->
          case
            registry_resolver.resolve_endpoint(
              endpoints,
              tenant_id,
              vendor,
              registry_resolver.from_active_session(active_session),
            )
          {
            Error(error) -> #(
              result.TransportFailed(
                reason: "endpoint_resolution_failed:"
                  <> registry_error_reason(error),
                retries: 0,
              ),
              replay_cache,
            )
            Ok(endpoint) ->
              case prepare(request_value, endpoint) {
                Error(error) -> #(
                  result.BuildRejected(reason: prepare_error_reason(error)),
                  replay_cache,
                )
                Ok(disconnect_plan) ->
                  case endpoint_secret(endpoint) {
                    Error(reason) -> #(
                      result.TransportFailed(reason: reason, retries: 0),
                      replay_cache,
                    )
                    Ok(secret) -> {
                      let transport_config =
                        shared_transport.from_endpoint(
                          endpoint,
                          secret,
                          now_seconds,
                        )
                      let DisconnectPlan(
                        request: prepared_request,
                        endpoint: prepared_endpoint,
                      ) = disconnect_plan

                      case
                        transport.prepare_roundtrip(
                          prepared_request,
                          transport_config,
                        )
                      {
                        Error(reason) -> #(
                          result.TransportFailed(
                            reason: "packet_prepare_failed:" <> reason,
                            retries: 0,
                          ),
                          replay_cache,
                        )
                        Ok(prepared) -> {
                          let types.NasEndpoint(
                            tenant_id: _endpoint_tenant_id,
                            endpoint_id: endpoint_id,
                            vendor: _endpoint_vendor,
                            transport: _endpoint_transport,
                            coa_host: _endpoint_host,
                            coa_port: _endpoint_port,
                            secret_ref: _endpoint_secret_ref,
                            timeout_ms: _endpoint_timeout_ms,
                            retry_profile_id: _endpoint_retry_profile_id,
                            nas_ip_address: _endpoint_nas_ip_address,
                            nas_identifier: _endpoint_nas_identifier,
                            capabilities: _endpoint_capabilities,
                          ) = prepared_endpoint
                          let transport.PreparedRoundtrip(
                            identifier: identifier,
                            request_authenticator: request_authenticator,
                            event_timestamp: event_timestamp,
                            payload: _payload,
                          ) = prepared

                          case
                            replay.validate_and_store(
                              replay_cache,
                              replay.ReplayEntry(
                                endpoint_id: endpoint_id,
                                identifier: identifier,
                                request_authenticator: request_authenticator,
                                event_timestamp: replay_event_timestamp(
                                  event_timestamp,
                                ),
                              ),
                              replay_window,
                              now_seconds,
                            )
                          {
                            Error(error) -> #(
                              result.ReplayRejected(reason: replay_error_reason(
                                error,
                              )),
                              replay_cache,
                            )
                            Ok(next_cache) -> #(
                              execute_live_prepared_attempts(
                                prepared,
                                transport_config,
                                retry_policy,
                                0,
                              ),
                              next_cache,
                            )
                          }
                        }
                      }
                    }
                  }
              }
          }
      }
  }
}

fn execute_live_attempts(
  request_value: request.DisconnectRequest,
  transport_config: shared_transport.CoaTransportConfig,
  retry_policy: retry.RetryPolicy,
  retries_used: Int,
) -> result.DisconnectExecutionResult {
  let retry.RetryPolicy(max_attempts: max_attempts, backoff_ms: _backoff_ms) =
    retry_policy
  let attempt = transport.roundtrip(request_value, transport_config)

  case attempt {
    response.Ack(_nas) -> result.Ack(retries: retries_used)
    response.Nak(_nas, error_code, error_message) ->
      result.Nak(
        code: error_code,
        message: error_message,
        retries: retries_used,
      )
    response.Malformed(reason) ->
      result.TransportFailed(
        reason: "malformed_response:" <> reason,
        retries: retries_used,
      )
    response.Timeout ->
      case is_retryable(attempt) && retries_used + 1 < max_attempts {
        True -> {
          let _delay = retry.retry_delay(retry_policy, retries_used)
          execute_live_attempts(
            request_value,
            transport_config,
            retry_policy,
            retries_used + 1,
          )
        }
        False -> result.Timeout(retries: retries_used)
      }
    response.TransportError(reason) ->
      case is_retryable(attempt) && retries_used + 1 < max_attempts {
        True -> {
          let _delay = retry.retry_delay(retry_policy, retries_used)
          execute_live_attempts(
            request_value,
            transport_config,
            retry_policy,
            retries_used + 1,
          )
        }
        False -> result.TransportFailed(reason: reason, retries: retries_used)
      }
  }
}

fn execute_live_prepared_attempts(
  prepared: transport.PreparedRoundtrip,
  transport_config: shared_transport.CoaTransportConfig,
  retry_policy: retry.RetryPolicy,
  retries_used: Int,
) -> result.DisconnectExecutionResult {
  let retry.RetryPolicy(max_attempts: max_attempts, backoff_ms: _backoff_ms) =
    retry_policy
  let attempt = transport.roundtrip_prepared(prepared, transport_config)

  case attempt {
    response.Ack(_nas) -> result.Ack(retries: retries_used)
    response.Nak(_nas, error_code, error_message) ->
      result.Nak(
        code: error_code,
        message: error_message,
        retries: retries_used,
      )
    response.Malformed(reason) ->
      result.TransportFailed(
        reason: "malformed_response:" <> reason,
        retries: retries_used,
      )
    response.Timeout ->
      case is_retryable(attempt) && retries_used + 1 < max_attempts {
        True -> {
          let _delay = retry.retry_delay(retry_policy, retries_used)
          execute_live_prepared_attempts(
            prepared,
            transport_config,
            retry_policy,
            retries_used + 1,
          )
        }
        False -> result.Timeout(retries: retries_used)
      }
    response.TransportError(reason) ->
      case is_retryable(attempt) && retries_used + 1 < max_attempts {
        True -> {
          let _delay = retry.retry_delay(retry_policy, retries_used)
          execute_live_prepared_attempts(
            prepared,
            transport_config,
            retry_policy,
            retries_used + 1,
          )
        }
        False -> result.TransportFailed(reason: reason, retries: retries_used)
      }
  }
}

fn is_retryable(response_value: response.DisconnectResponse) -> Bool {
  case response_value {
    response.Timeout -> True
    response.TransportError(_) -> True
    _ -> False
  }
}

fn build_error_reason(error: request.BuildError) -> String {
  case error {
    request.MissingSessionSelector -> "missing_session_selector"
    request.UnsupportedCommand(command_name) ->
      "unsupported_disconnect_command:" <> command_name
  }
}

fn prepare_error_reason(error: DisconnectPreparationError) -> String {
  case error {
    DisconnectUnsupportedByEndpoint(endpoint_id) ->
      "disconnect_unsupported_by_endpoint:" <> endpoint_id
    UnsupportedTransport(kind) ->
      "unsupported_transport:" <> transport_kind(kind)
  }
}

fn session_error_reason(error: session_types.SessionResolutionError) -> String {
  case error {
    session_types.NoActiveSession -> "no_active_session"
    session_types.AmbiguousSession -> "ambiguous_active_session"
    session_types.StaleSession(max_age_seconds) ->
      "stale_session:max_age_seconds:" <> int.to_string(max_age_seconds)
  }
}

fn replay_error_reason(error: replay.ReplayError) -> String {
  case error {
    replay.InvalidReplayWindow -> "invalid_replay_window"
    replay.MissingEventTimestamp -> "missing_event_timestamp"
    replay.StaleEventTimestamp -> "stale_event_timestamp"
    replay.DuplicateRequest -> "duplicate_request"
  }
}

fn replay_event_timestamp(event_timestamp: option.Option(Int)) -> Int {
  case event_timestamp {
    option.Some(value) -> value
    option.None -> 0
  }
}

fn registry_error_reason(error: types.RegistryError) -> String {
  case error {
    types.MissingEndpointSelector -> "missing_endpoint_selector"
    types.NoEndpointMatch -> "no_endpoint_match"
    types.MultipleEndpointMatches -> "multiple_endpoint_matches"
    types.InvalidEndpoint(reason) -> "invalid_endpoint:" <> reason
  }
}

fn transport_kind(kind: types.TransportKind) -> String {
  case kind {
    types.Udp -> "udp"
    types.RadSec -> "radsec"
  }
}

fn endpoint_secret(endpoint: types.NasEndpoint) -> Result(String, String) {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: _endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: _capabilities,
  ) = endpoint

  case secret_ref {
    types.InlineSecret(value) -> Ok(value)
    types.EnvSecret(name) -> Error("unsupported_secret_ref:env:" <> name)
    types.VaultSecret(path, key) ->
      Error("unsupported_secret_ref:vault:" <> path <> ":" <> key)
  }
}
