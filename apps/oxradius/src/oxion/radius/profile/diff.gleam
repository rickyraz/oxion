import oxion/radius/profile/normalizer
import oxion/radius/profile/snapshot
import oxion/radius/profile/types
import oxion/radius/vendor/types as vendor_types

pub type ProfileDiff {
  AlreadyApplied
  RequiresUpdate(
    current: List(vendor_types.RadiusAttribute),
    target: List(vendor_types.RadiusAttribute),
  )
}

pub fn compare(
  current_snapshot: snapshot.ActiveProfileSnapshot,
  target: types.ResolvedTarget,
) -> ProfileDiff {
  let snapshot.ActiveProfileSnapshot(
    service_id: _service_id,
    selector: _selector,
    profile_id: _profile_id,
    attributes: current_attributes,
    session_active: _session_active,
  ) = current_snapshot
  let types.ResolvedTarget(target_id: _target_id, attributes: target_attributes) =
    target

  let normalized_current = normalizer.normalize_attributes(current_attributes)
  let normalized_target = normalizer.normalize_attributes(target_attributes)

  case normalized_current == normalized_target {
    True -> AlreadyApplied
    False ->
      RequiresUpdate(current: normalized_current, target: normalized_target)
  }
}
