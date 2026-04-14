import gleam/list
import gleam/option
import oxion/radius/profile/snapshot
import oxion/radius/registry/types
import oxion/radius/session/types as session_types
import oxion/radius/vendor/types as vendor_types

pub fn from_session_selector(
  selector: snapshot.SessionSelector,
) -> types.EndpointSelector {
  let snapshot.SessionSelector(
    username: _username,
    framed_ip: _framed_ip,
    acct_session_id: _acct_session_id,
    nas_ip_address: nas_ip_address,
  ) = selector

  types.EndpointSelector(
    nas_ip_address: nas_ip_address,
    nas_identifier: option.None,
  )
}

pub fn from_active_session(
  session: session_types.ActiveSession,
) -> types.EndpointSelector {
  let session_types.ActiveSession(
    tenant_id: _tenant_id,
    service_id: _service_id,
    username: _username,
    acct_session_id: _acct_session_id,
    framed_ip: _framed_ip,
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
    active_profile_id: _active_profile_id,
    attributes: _attributes,
    last_accounting_epoch_seconds: _last_accounting_epoch_seconds,
    session_active: _session_active,
  ) = session

  types.EndpointSelector(
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
  )
}

// Why: endpoint selection must be deterministic and fail closed because the
// transport secret is bound to the NAS peer, not to business intent.
pub fn resolve_endpoint(
  endpoints: List(types.NasEndpoint),
  tenant_id: String,
  vendor: vendor_types.RadiusVendor,
  selector: types.EndpointSelector,
) -> Result(types.NasEndpoint, types.RegistryError) {
  case has_selector_value(selector) {
    False -> Error(types.MissingEndpointSelector)
    True ->
      case
        list.filter(endpoints, fn(endpoint) {
          matches_tenant_vendor(endpoint, tenant_id, vendor)
          && matches_selector(endpoint, selector)
        })
      {
        [] -> Error(types.NoEndpointMatch)
        [endpoint] -> validate_endpoint(endpoint)
        _ -> Error(types.MultipleEndpointMatches)
      }
  }
}

fn matches_tenant_vendor(
  endpoint: types.NasEndpoint,
  tenant_id: String,
  vendor: vendor_types.RadiusVendor,
) -> Bool {
  let types.NasEndpoint(
    tenant_id: endpoint_tenant_id,
    endpoint_id: _endpoint_id,
    vendor: endpoint_vendor,
    transport: _transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: _capabilities,
  ) = endpoint

  endpoint_tenant_id == tenant_id && endpoint_vendor == vendor
}

fn matches_selector(
  endpoint: types.NasEndpoint,
  selector: types.EndpointSelector,
) -> Bool {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: _endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: _coa_host,
    coa_port: _coa_port,
    secret_ref: _secret_ref,
    timeout_ms: _timeout_ms,
    retry_profile_id: _retry_profile_id,
    nas_ip_address: endpoint_nas_ip_address,
    nas_identifier: endpoint_nas_identifier,
    capabilities: _capabilities,
  ) = endpoint
  let types.EndpointSelector(
    nas_ip_address: selector_nas_ip_address,
    nas_identifier: selector_nas_identifier,
  ) = selector

  option_matches(endpoint_nas_ip_address, selector_nas_ip_address)
  && option_matches(endpoint_nas_identifier, selector_nas_identifier)
}

fn option_matches(
  expected: option.Option(String),
  actual: option.Option(String),
) -> Bool {
  case expected {
    option.None -> True
    option.Some(expected_value) ->
      case actual {
        option.Some(actual_value) -> expected_value == actual_value
        option.None -> False
      }
  }
}

fn has_selector_value(selector: types.EndpointSelector) -> Bool {
  let types.EndpointSelector(
    nas_ip_address: nas_ip_address,
    nas_identifier: nas_identifier,
  ) = selector

  case nas_ip_address {
    option.Some(_) -> True
    option.None ->
      case nas_identifier {
        option.Some(_) -> True
        option.None -> False
      }
  }
}

fn validate_endpoint(
  endpoint: types.NasEndpoint,
) -> Result(types.NasEndpoint, types.RegistryError) {
  let types.NasEndpoint(
    tenant_id: _tenant_id,
    endpoint_id: _endpoint_id,
    vendor: _vendor,
    transport: _transport,
    coa_host: coa_host,
    coa_port: coa_port,
    secret_ref: _secret_ref,
    timeout_ms: timeout_ms,
    retry_profile_id: retry_profile_id,
    nas_ip_address: _nas_ip_address,
    nas_identifier: _nas_identifier,
    capabilities: _capabilities,
  ) = endpoint

  case coa_host == "" {
    True -> Error(types.InvalidEndpoint(reason: "missing_coa_host"))
    False ->
      case coa_port > 0 {
        False -> Error(types.InvalidEndpoint(reason: "invalid_coa_port"))
        True ->
          case timeout_ms > 0 {
            False -> Error(types.InvalidEndpoint(reason: "invalid_timeout_ms"))
            True ->
              case retry_profile_id == "" {
                True ->
                  Error(types.InvalidEndpoint(
                    reason: "missing_retry_profile_id",
                  ))
                False -> Ok(endpoint)
              }
          }
      }
  }
}
