import gleam/option
import oxion/radius/profile/diff
import oxion/radius/profile/snapshot
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

pub fn profile_diff_normalizes_order_and_duplicates_test() {
  let current_snapshot =
    snapshot.ActiveProfileSnapshot(
      service_id: "svc_1",
      selector: snapshot.SessionSelector(
        username: option.Some("cust_001"),
        framed_ip: option.None,
        acct_session_id: option.None,
        nas_ip_address: option.None,
      ),
      profile_id: option.Some("bw_4mbps"),
      attributes: [
        vendor_types.RadiusAttribute(
          name: "class",
          value: "throttled_due_overdue",
        ),
        vendor_types.RadiusAttribute(name: "cisco.qos_up", value: "4096"),
        vendor_types.RadiusAttribute(
          name: "cisco.service_profile",
          value: "bw_4mbps",
        ),
        vendor_types.RadiusAttribute(name: "cisco.qos_up", value: "4096"),
        vendor_types.RadiusAttribute(name: "cisco.qos_down", value: "4096"),
      ],
      session_active: True,
    )
  let target =
    types.ResolvedTarget(target_id: "bw_4mbps", attributes: [
      vendor_types.RadiusAttribute(name: "cisco.qos_down", value: "4096"),
      vendor_types.RadiusAttribute(
        name: "cisco.service_profile",
        value: "bw_4mbps",
      ),
      vendor_types.RadiusAttribute(
        name: "class",
        value: "throttled_due_overdue",
      ),
      vendor_types.RadiusAttribute(name: "cisco.qos_up", value: "4096"),
    ])

  assert diff.compare(current_snapshot, target) == diff.AlreadyApplied
}
