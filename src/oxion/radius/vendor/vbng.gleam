import gleam/int
import oxion/radius/profile/types as profile_types
import oxion/radius/vendor/types

pub fn render_profile(
  profile: profile_types.ProfileDefinition,
  target_state: String,
) -> Result(List(types.RadiusAttribute), types.VendorAdapterError) {
  let profile_types.ProfileDefinition(
    profile_id: _profile_id,
    service_profile_id: service_profile_id,
    download_kbps: download_kbps,
    upload_kbps: upload_kbps,
  ) = profile

  case service_profile_id == "" {
    True -> Error(types.MissingRequiredField(field: "service_profile_id"))
    False ->
      case download_kbps > 0 && upload_kbps > 0 {
        False -> Error(types.InvalidBandwidth(field: "download_or_upload_kbps"))
        True ->
          Ok([
            types.RadiusAttribute(
              name: "vbng.profile_id",
              value: service_profile_id,
            ),
            types.RadiusAttribute(
              name: "vbng.down_kbps",
              value: int.to_string(download_kbps),
            ),
            types.RadiusAttribute(
              name: "vbng.up_kbps",
              value: int.to_string(upload_kbps),
            ),
            types.RadiusAttribute(name: "policy_tag", value: target_state),
          ])
      }
  }
}

pub fn render_suspend(
  target_state: String,
  reason: String,
) -> Result(List(types.RadiusAttribute), types.VendorAdapterError) {
  case reason == "" {
    True -> Error(types.MissingRequiredField(field: "suspend_reason"))
    False ->
      Ok([
        types.RadiusAttribute(name: "vbng.access_action", value: "suspend"),
        types.RadiusAttribute(name: "policy_tag", value: target_state),
        types.RadiusAttribute(name: "reason", value: reason),
      ])
  }
}
