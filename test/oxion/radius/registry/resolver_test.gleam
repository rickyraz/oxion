import gleam/option
import oxion/radius/profile/snapshot
import oxion/radius/registry/capability
import oxion/radius/registry/resolver
import oxion/radius/registry/types
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

fn sample_selector() -> snapshot.SessionSelector {
  snapshot.SessionSelector(
    username: option.None,
    framed_ip: option.None,
    acct_session_id: option.None,
    nas_ip_address: option.Some("10.0.0.1"),
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
