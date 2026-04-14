import oxion/platform/dsr/types

pub type AdapterError {
  UnsupportedStore(store_name: types.StoreName)
}

pub type CoreStore {
  CoreStore(
    exported_subjects: List(String),
    restricted_subjects: List(String),
    retained_subjects: List(String),
    reviewed_subjects: List(String),
  )
}

pub fn empty() -> CoreStore {
  CoreStore(
    exported_subjects: [],
    restricted_subjects: [],
    retained_subjects: [],
    reviewed_subjects: [],
  )
}

pub fn apply(
  store: CoreStore,
  subject_ref: String,
  item: types.RequestItem,
) -> Result(#(CoreStore, types.ExecutionResolution), AdapterError) {
  let types.RequestItem(
    store_name: store_name,
    action: action,
    note: _note,
    resolution: _resolution,
  ) = item

  case store_name {
    types.ConsentRecords | types.Backups ->
      case action {
        types.ExportStore ->
          Ok(#(export_subject(store, subject_ref), types.Exported))
        types.RestrictStore ->
          Ok(#(restrict_subject(store, subject_ref), types.Restricted))
        types.RetainStore ->
          Ok(#(retain_subject(store, subject_ref), types.Retained))
        types.ReviewStore ->
          Ok(#(review_subject(store, subject_ref), types.Reviewed))
        types.NoAction -> Ok(#(store, types.NotApplicable))
        _ -> Ok(#(store, types.NotApplicable))
      }

    _ -> Error(UnsupportedStore(store_name: store_name))
  }
}

fn export_subject(store: CoreStore, subject_ref: String) -> CoreStore {
  let CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: restricted_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  CoreStore(
    exported_subjects: [subject_ref, ..exported_subjects],
    restricted_subjects: restricted_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn restrict_subject(store: CoreStore, subject_ref: String) -> CoreStore {
  let CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: restricted_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: [subject_ref, ..restricted_subjects],
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn retain_subject(store: CoreStore, subject_ref: String) -> CoreStore {
  let CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: restricted_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: restricted_subjects,
    retained_subjects: [subject_ref, ..retained_subjects],
    reviewed_subjects: reviewed_subjects,
  )
}

fn review_subject(store: CoreStore, subject_ref: String) -> CoreStore {
  let CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: restricted_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  CoreStore(
    exported_subjects: exported_subjects,
    restricted_subjects: restricted_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: [subject_ref, ..reviewed_subjects],
  )
}
