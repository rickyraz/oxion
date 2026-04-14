import oxion/radius/vendor/types as vendor_types

pub type ProfileDefinition {
  ProfileDefinition(
    profile_id: String,
    service_profile_id: String,
    download_kbps: Int,
    upload_kbps: Int,
  )
}

pub type ResolvedTarget {
  ResolvedTarget(
    target_id: String,
    attributes: List(vendor_types.RadiusAttribute),
  )
}

pub type ProfileResolutionError {
  ProfileNotFound(profile_id: String)
  InvalidProfileDefinition(profile_id: String, reason: String)
  VendorMappingFailed(reason: String)
}
