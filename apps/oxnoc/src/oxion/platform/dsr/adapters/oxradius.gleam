import oxion/platform/dsr/types

pub type AdapterError {
  UnsupportedStore(store_name: types.StoreName)
}

pub type RadiusStore {
  RadiusStore(
    exported_subjects: List(String),
    deleted_profiles: List(String),
    deleted_sessions: List(String),
    restricted_subjects: List(String),
    reviewed_subjects: List(String),
  )
}

pub fn empty() -> RadiusStore {
  RadiusStore(
    exported_subjects: [],
    deleted_profiles: [],
    deleted_sessions: [],
    restricted_subjects: [],
    reviewed_subjects: [],
  )
}

pub fn apply(
  store: RadiusStore,
  subject_ref: String,
  item: types.RequestItem,
) -> Result(#(RadiusStore, types.ExecutionResolution), AdapterError) {
  let types.RequestItem(
    store_name: store_name,
    action: action,
    note: _note,
    resolution: _resolution,
  ) = item

  case store_name {
    types.SubscriberProfile ->
      case action {
        types.ExportStore ->
          Ok(#(export_subject(store, subject_ref), types.Exported))
        types.DeleteStore ->
          Ok(#(delete_profile(store, subject_ref), types.Deleted))
        types.RestrictStore ->
          Ok(#(restrict_subject(store, subject_ref), types.Restricted))
        types.ReviewStore ->
          Ok(#(review_subject(store, subject_ref), types.Reviewed))
        types.NoAction -> Ok(#(store, types.NotApplicable))
        _ -> Ok(#(store, types.NotApplicable))
      }

    types.ActiveSessions ->
      case action {
        types.ExportStore ->
          Ok(#(export_subject(store, subject_ref), types.Exported))
        types.DeleteStore ->
          Ok(#(delete_session(store, subject_ref), types.Deleted))
        types.RestrictStore ->
          Ok(#(restrict_subject(store, subject_ref), types.Restricted))
        types.ReviewStore ->
          Ok(#(review_subject(store, subject_ref), types.Reviewed))
        types.NoAction -> Ok(#(store, types.NotApplicable))
        _ -> Ok(#(store, types.NotApplicable))
      }

    _ -> Error(UnsupportedStore(store_name: store_name))
  }
}

fn export_subject(store: RadiusStore, subject_ref: String) -> RadiusStore {
  let RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  RadiusStore(
    exported_subjects: [subject_ref, ..exported_subjects],
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn delete_profile(store: RadiusStore, subject_ref: String) -> RadiusStore {
  let RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: [subject_ref, ..deleted_profiles],
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn delete_session(store: RadiusStore, subject_ref: String) -> RadiusStore {
  let RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: [subject_ref, ..deleted_sessions],
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn restrict_subject(store: RadiusStore, subject_ref: String) -> RadiusStore {
  let RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: [subject_ref, ..restricted_subjects],
    reviewed_subjects: reviewed_subjects,
  )
}

fn review_subject(store: RadiusStore, subject_ref: String) -> RadiusStore {
  let RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  RadiusStore(
    exported_subjects: exported_subjects,
    deleted_profiles: deleted_profiles,
    deleted_sessions: deleted_sessions,
    restricted_subjects: restricted_subjects,
    reviewed_subjects: [subject_ref, ..reviewed_subjects],
  )
}
