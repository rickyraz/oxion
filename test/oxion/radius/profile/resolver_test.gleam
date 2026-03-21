import oxion/orchestration/collection/commands
import oxion/radius/profile/resolver
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

pub fn resolver_maps_cisco_profile_definition_test() {
  let registry = [
    types.ProfileDefinition(
      profile_id: "bw_4mbps",
      service_profile_id: "bw_4mbps",
      download_kbps: 4096,
      upload_kbps: 4096,
    ),
  ]
  let plan =
    commands.CommandPlan(
      action_fingerprint: "fp:soft:0",
      stage_id: "soft_throttle",
      action_name: "apply_bandwidth_profile",
      route: commands.RadiusRoute,
      command: commands.ChangePackage(
        service_id: "svc_1",
        target_profile_id: "bw_4mbps",
      ),
      target_state: "throttled_due_overdue",
    )

  case resolver.resolve_plan_target(plan, registry, vendor_types.Cisco) {
    Ok(types.ResolvedTarget(target_id: target_id, attributes: attributes)) -> {
      assert target_id == "bw_4mbps"
      assert attributes
        == [
          vendor_types.RadiusAttribute(
            name: "cisco.service_profile",
            value: "bw_4mbps",
          ),
          vendor_types.RadiusAttribute(name: "cisco.qos_down", value: "4096"),
          vendor_types.RadiusAttribute(name: "cisco.qos_up", value: "4096"),
          vendor_types.RadiusAttribute(
            name: "class",
            value: "throttled_due_overdue",
          ),
        ]
    }
    Error(_) -> panic
  }
}
