import gleam/option
import oxion/radius/profile/snapshot
import oxion/radius/registry/capability
import oxion/radius/registry/resolver
import oxion/radius/registry/types
import oxion/radius/session/types as session_types
import oxion/radius/vendor/types as vendor_types

pub fn resolver_matches_endpoint_by_tenant_vendor_and_nas_ip_test() {
  assert resolver.resolve_endpoint(
      sample_endpoints(),
      "tenant_a",
      vendor_types.Cisco,
      types.EndpointSelector(
        nas_ip_address: option.Some("10.0.0.1"),
        nas_identifier: option.None,
      ),
    )
    == Ok(first_endpoint())
}

pub fn resolver_converts_session_selector_to_lookup_context_test() {
  assert resolver.from_session_selector(sample_selector())
    == types.EndpointSelector(
      nas_ip_address: option.Some("10.0.0.1"),
      nas_identifier: option.None,
    )
}

pub fn resolver_converts_active_session_to_lookup_context_test() {
  assert resolver.from_active_session(sample_active_session())
    == types.EndpointSelector(
      nas_ip_address: option.None,
      nas_identifier: option.Some("edge-a"),
    )
}

pub fn resolver_rejects_empty_selector_test() {
  assert resolver.resolve_endpoint(
      sample_endpoints(),
      "tenant_a",
      vendor_types.Cisco,
      types.EndpointSelector(
        nas_ip_address: option.None,
        nas_identifier: option.None,
      ),
    )
    == Error(types.MissingEndpointSelector)
}

fn sample_selector() -> snapshot.SessionSelector {
  snapshot.SessionSelector(
    username: option.None,
    framed_ip: option.None,
    acct_session_id: option.None,
    nas_ip_address: option.Some("10.0.0.1"),
  )
}

fn sample_active_session() -> session_types.ActiveSession {
  session_types.ActiveSession(
    tenant_id: "tenant_a",
    service_id: "svc_1",
    username: option.Some("cust_001"),
    acct_session_id: option.Some("sess-1"),
    framed_ip: option.Some("10.10.20.5"),
    nas_ip_address: option.None,
    nas_identifier: option.Some("edge-a"),
    active_profile_id: option.Some("svc_home_100m"),
    attributes: [],
    last_accounting_epoch_seconds: 100,
    session_active: True,
  )
}

fn first_endpoint() -> types.NasEndpoint {
  types.NasEndpoint(
    tenant_id: "tenant_a",
    endpoint_id: "edge_1",
    vendor: vendor_types.Cisco,
    transport: types.Udp,
    coa_host: "10.0.0.1",
    coa_port: 3799,
    secret_ref: types.InlineSecret(value: "secret"),
    timeout_ms: 1000,
    retry_profile_id: "default_udp",
    nas_ip_address: option.Some("10.0.0.1"),
    nas_identifier: option.None,
    capabilities: capability.default_udp_capabilities(),
  )
}

fn sample_endpoints() -> List(types.NasEndpoint) {
  [
    first_endpoint(),
    types.NasEndpoint(
      tenant_id: "tenant_a",
      endpoint_id: "edge_2",
      vendor: vendor_types.Juniper,
      transport: types.Udp,
      coa_host: "10.0.0.2",
      coa_port: 3799,
      secret_ref: types.InlineSecret(value: "secret"),
      timeout_ms: 1000,
      retry_profile_id: "default_udp",
      nas_ip_address: option.Some("10.0.0.2"),
      nas_identifier: option.None,
      capabilities: capability.default_udp_capabilities(),
    ),
  ]
}
