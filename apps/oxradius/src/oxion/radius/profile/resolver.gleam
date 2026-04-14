import gleam/list
import oxion/orchestration/collection/commands
import oxion/radius/profile/types
import oxion/radius/vendor/cisco
import oxion/radius/vendor/juniper
import oxion/radius/vendor/types as vendor_types
import oxion/radius/vendor/vbng

pub fn resolve_plan_target(
  plan: commands.CommandPlan,
  registry: List(types.ProfileDefinition),
  vendor: vendor_types.RadiusVendor,
) -> Result(types.ResolvedTarget, types.ProfileResolutionError) {
  let commands.CommandPlan(
    action_fingerprint: _action_fingerprint,
    stage_id: _stage_id,
    action_name: _action_name,
    route: _route,
    command: command,
    target_state: target_state,
  ) = plan

  case command {
    commands.ChangePackage(
      service_id: _service_id,
      target_profile_id: profile_id,
    ) -> resolve_profile(profile_id, registry, vendor, target_state)

    commands.RestoreService(
      service_id: _service_id,
      original_profile_id: profile_id,
    ) -> resolve_profile(profile_id, registry, vendor, target_state)

    commands.SuspendService(service_id: _service_id, reason: reason) ->
      case render_suspend(vendor, target_state, reason) {
        Ok(attributes) ->
          Ok(types.ResolvedTarget(target_id: "suspend", attributes: attributes))
        Error(error) ->
          Error(types.VendorMappingFailed(reason: vendor_error_reason(error)))
      }
  }
}

fn resolve_profile(
  profile_id: String,
  registry: List(types.ProfileDefinition),
  vendor: vendor_types.RadiusVendor,
  target_state: String,
) -> Result(types.ResolvedTarget, types.ProfileResolutionError) {
  case find_profile(registry, profile_id) {
    Ok(profile) ->
      case render_profile(vendor, profile, target_state) {
        Ok(attributes) ->
          Ok(types.ResolvedTarget(target_id: profile_id, attributes: attributes))
        Error(error) ->
          Error(types.VendorMappingFailed(reason: vendor_error_reason(error)))
      }

    Error(error) -> Error(error)
  }
}

fn find_profile(
  registry: List(types.ProfileDefinition),
  profile_id: String,
) -> Result(types.ProfileDefinition, types.ProfileResolutionError) {
  case
    list.find(registry, fn(profile) {
      let types.ProfileDefinition(
        profile_id: candidate_profile_id,
        service_profile_id: _service_profile_id,
        download_kbps: _download_kbps,
        upload_kbps: _upload_kbps,
      ) = profile
      candidate_profile_id == profile_id
    })
  {
    Ok(profile) -> Ok(profile)
    Error(_) -> Error(types.ProfileNotFound(profile_id: profile_id))
  }
}

fn render_profile(
  vendor: vendor_types.RadiusVendor,
  profile: types.ProfileDefinition,
  target_state: String,
) -> Result(List(vendor_types.RadiusAttribute), vendor_types.VendorAdapterError) {
  case vendor {
    vendor_types.Cisco -> cisco.render_profile(profile, target_state)
    vendor_types.Juniper -> juniper.render_profile(profile, target_state)
    vendor_types.Vbng -> vbng.render_profile(profile, target_state)
  }
}

fn render_suspend(
  vendor: vendor_types.RadiusVendor,
  target_state: String,
  reason: String,
) -> Result(List(vendor_types.RadiusAttribute), vendor_types.VendorAdapterError) {
  case vendor {
    vendor_types.Cisco -> cisco.render_suspend(target_state, reason)
    vendor_types.Juniper -> juniper.render_suspend(target_state, reason)
    vendor_types.Vbng -> vbng.render_suspend(target_state, reason)
  }
}

fn vendor_error_reason(error: vendor_types.VendorAdapterError) -> String {
  case error {
    vendor_types.MissingRequiredField(field) ->
      "missing_required_field:" <> field
    vendor_types.InvalidBandwidth(field) -> "invalid_bandwidth:" <> field
    vendor_types.UnsupportedAccessAction(action) ->
      "unsupported_access_action:" <> action
  }
}
