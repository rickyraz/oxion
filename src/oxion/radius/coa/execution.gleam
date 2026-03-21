import gleam/int
import gleam/option
import oxion/orchestration/collection/commands
import oxion/radius/coa/request
import oxion/radius/coa/response
import oxion/radius/coa/result
import oxion/radius/coa/retry
import oxion/radius/coa/transport
import oxion/radius/profile/diff
import oxion/radius/profile/resolver
import oxion/radius/profile/snapshot
import oxion/radius/profile/types as profile_types
import oxion/radius/registry/resolver as registry_resolver
import oxion/radius/registry/types as registry_types
import oxion/radius/session/resolver as session_resolver
import oxion/radius/session/types as session_types
import oxion/radius/vendor/types as vendor_types

pub fn send_coa_if_needed(
  plan: commands.CommandPlan,
  vendor: vendor_types.RadiusVendor,
  selector: snapshot.SessionSelector,
  active_snapshot: option.Option(snapshot.ActiveProfileSnapshot),
  profile_registry: List(profile_types.ProfileDefinition),
  retry_policy: retry.RetryPolicy,
  attempts: List(response.CoaResponse),
) -> result.CoaExecutionResult {
  case retry.validate(retry_policy) {
    Error(retry.InvalidMaxAttempts) ->
      result.InvalidRetryPolicy(reason: "invalid_max_attempts")
    Error(retry.EmptyBackoffSchedule) ->
      result.InvalidRetryPolicy(reason: "empty_backoff_schedule")
    Ok(_) ->
      case
        prepare_request(
          plan,
          vendor,
          selector,
          active_snapshot,
          profile_registry,
        )
      {
        Ok(#(_request_value, _target_id)) ->
          execute_attempts(attempts, retry_policy, 0)
        Error(execution_result) -> execution_result
      }
  }
}

// Why: CoA execution must compare current vs target before packet emission so
// duplicate scheduler runs cannot devolve into repeated network writes.
fn prepare_request(
  plan: commands.CommandPlan,
  vendor: vendor_types.RadiusVendor,
  selector: snapshot.SessionSelector,
  active_snapshot: option.Option(snapshot.ActiveProfileSnapshot),
  profile_registry: List(profile_types.ProfileDefinition),
) -> Result(#(request.CoaRequest, String), result.CoaExecutionResult) {
  case resolver.resolve_plan_target(plan, profile_registry, vendor) {
    Error(error) ->
      Error(
        result.ProfileResolutionFailed(reason: resolution_error_reason(error)),
      )
    Ok(target) ->
      case active_snapshot {
        option.None ->
          Error(result.SnapshotUnavailable(reason: "active_snapshot_missing"))
        option.Some(current_snapshot) -> {
          let snapshot.ActiveProfileSnapshot(
            service_id: _service_id,
            selector: _current_selector,
            profile_id: _profile_id,
            attributes: _current_attributes,
            session_active: session_active,
          ) = current_snapshot

          case session_active {
            False ->
              Error(result.SnapshotUnavailable(reason: "session_not_active"))
            True ->
              case diff.compare(current_snapshot, target) {
                diff.AlreadyApplied ->
                  Error(result.IdempotentSkip(
                    reason: "target_profile_already_active",
                  ))

                diff.RequiresUpdate(current: _current, target: _target) -> {
                  let profile_types.ResolvedTarget(
                    target_id: target_id,
                    attributes: _attributes,
                  ) = target

                  case request.build_request(plan, selector, target) {
                    Error(request.MissingSessionSelector) ->
                      Error(result.BuildRejected(
                        reason: "missing_session_selector",
                      ))
                    Error(request.EmptyTargetAttributes) ->
                      Error(result.BuildRejected(
                        reason: "empty_target_attributes",
                      ))
                    Ok(request_value) -> Ok(#(request_value, target_id))
                  }
                }
              }
          }
        }
      }
  }
}

pub fn send_coa_live(
  plan: commands.CommandPlan,
  vendor: vendor_types.RadiusVendor,
  selector: snapshot.SessionSelector,
  active_snapshot: option.Option(snapshot.ActiveProfileSnapshot),
  profile_registry: List(profile_types.ProfileDefinition),
  retry_policy: retry.RetryPolicy,
  transport_config: transport.CoaTransportConfig,
) -> result.CoaExecutionResult {
  case retry.validate(retry_policy) {
    Error(retry.InvalidMaxAttempts) ->
      result.InvalidRetryPolicy(reason: "invalid_max_attempts")
    Error(retry.EmptyBackoffSchedule) ->
      result.InvalidRetryPolicy(reason: "empty_backoff_schedule")
    Ok(_) ->
      case
        prepare_request(
          plan,
          vendor,
          selector,
          active_snapshot,
          profile_registry,
        )
      {
        Ok(#(request_value, target_id)) ->
          execute_live_attempts(
            request_value,
            vendor,
            target_id,
            transport_config,
            retry_policy,
            0,
          )
        Error(execution_result) -> execution_result
      }
  }
}

pub fn send_coa_live_managed(
  plan: commands.CommandPlan,
  vendor: vendor_types.RadiusVendor,
  session_lookup: session_types.SessionLookup,
  session_max_age_seconds: Int,
  endpoints: List(registry_types.NasEndpoint),
  sessions: List(session_types.ActiveSession),
  profile_registry: List(profile_types.ProfileDefinition),
  retry_policy: retry.RetryPolicy,
  now_seconds: Int,
) -> result.CoaExecutionResult {
  let session_types.SessionLookup(
    tenant_id: tenant_id,
    service_id: _service_id,
    username: _username,
    acct_session_id: _acct_session_id,
    framed_ip: _framed_ip,
  ) = session_lookup

  // Why: the managed live path should derive active session and endpoint state
  // from adapter-owned runtime models so transport config stops being caller
  // assembled by hand.
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
    Ok(active_session) -> {
      let active_snapshot = session_resolver.to_snapshot(active_session)
      let snapshot.ActiveProfileSnapshot(
        service_id: _snapshot_service_id,
        selector: selector,
        profile_id: _snapshot_profile_id,
        attributes: _snapshot_attributes,
        session_active: _snapshot_session_active,
      ) = active_snapshot

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
          case endpoint_secret(endpoint) {
            Error(reason) -> result.TransportFailed(reason: reason, retries: 0)
            Ok(secret) ->
              send_coa_live(
                plan,
                vendor,
                selector,
                option.Some(active_snapshot),
                profile_registry,
                retry_policy,
                transport.from_endpoint(endpoint, secret, now_seconds),
              )
          }
      }
    }
  }
}

fn execute_attempts(
  attempts: List(response.CoaResponse),
  retry_policy: retry.RetryPolicy,
  retries_used: Int,
) -> result.CoaExecutionResult {
  let retry.RetryPolicy(max_attempts: max_attempts, backoff_ms: _backoff_ms) =
    retry_policy

  case attempts {
    [] ->
      result.TransportFailed(
        reason: "no_response_attempts_available",
        retries: retries_used,
      )

    [attempt, ..rest] ->
      case attempt {
        response.Ack(_nas, applied_target) ->
          result.Ack(applied_target: applied_target, retries: retries_used)

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
          case
            retry.is_retryable(attempt)
            && retries_used + 1 < max_attempts
            && rest != []
          {
            True -> {
              let _delay = retry.retry_delay(retry_policy, retries_used)
              execute_attempts(rest, retry_policy, retries_used + 1)
            }
            False -> result.Timeout(retries: retries_used)
          }

        response.TransportError(reason) ->
          case
            retry.is_retryable(attempt)
            && retries_used + 1 < max_attempts
            && rest != []
          {
            True -> {
              let _delay = retry.retry_delay(retry_policy, retries_used)
              execute_attempts(rest, retry_policy, retries_used + 1)
            }
            False ->
              result.TransportFailed(reason: reason, retries: retries_used)
          }
      }
  }
}

fn execute_live_attempts(
  request_value: request.CoaRequest,
  vendor: vendor_types.RadiusVendor,
  target_id: String,
  transport_config: transport.CoaTransportConfig,
  retry_policy: retry.RetryPolicy,
  retries_used: Int,
) -> result.CoaExecutionResult {
  let retry.RetryPolicy(max_attempts: max_attempts, backoff_ms: _backoff_ms) =
    retry_policy
  let attempt =
    transport.roundtrip(request_value, vendor, target_id, transport_config)

  case attempt {
    response.Ack(_nas, applied_target) ->
      result.Ack(applied_target: applied_target, retries: retries_used)

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
      case retry.is_retryable(attempt) && retries_used + 1 < max_attempts {
        True -> {
          let _delay = retry.retry_delay(retry_policy, retries_used)
          execute_live_attempts(
            request_value,
            vendor,
            target_id,
            transport_config,
            retry_policy,
            retries_used + 1,
          )
        }
        False -> result.Timeout(retries: retries_used)
      }

    response.TransportError(reason) ->
      case retry.is_retryable(attempt) && retries_used + 1 < max_attempts {
        True -> {
          let _delay = retry.retry_delay(retry_policy, retries_used)
          execute_live_attempts(
            request_value,
            vendor,
            target_id,
            transport_config,
            retry_policy,
            retries_used + 1,
          )
        }
        False -> result.TransportFailed(reason: reason, retries: retries_used)
      }
  }
}

fn resolution_error_reason(
  error: profile_types.ProfileResolutionError,
) -> String {
  case error {
    profile_types.ProfileNotFound(profile_id) ->
      "profile_not_found:" <> profile_id
    profile_types.InvalidProfileDefinition(profile_id, reason) ->
      "invalid_profile_definition:" <> profile_id <> ":" <> reason
    profile_types.VendorMappingFailed(reason) ->
      "vendor_mapping_failed:" <> reason
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

fn registry_error_reason(error: registry_types.RegistryError) -> String {
  case error {
    registry_types.MissingEndpointSelector -> "missing_endpoint_selector"
    registry_types.NoEndpointMatch -> "no_endpoint_match"
    registry_types.MultipleEndpointMatches -> "multiple_endpoint_matches"
    registry_types.InvalidEndpoint(reason) -> "invalid_endpoint:" <> reason
  }
}

fn endpoint_secret(
  endpoint: registry_types.NasEndpoint,
) -> Result(String, String) {
  let registry_types.NasEndpoint(
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
    registry_types.InlineSecret(value) -> Ok(value)
    registry_types.EnvSecret(name) ->
      Error("unsupported_secret_ref:env:" <> name)
    registry_types.VaultSecret(path, key) ->
      Error("unsupported_secret_ref:vault:" <> path <> ":" <> key)
  }
}
