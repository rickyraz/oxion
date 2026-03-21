import oxion/platform/dsr/types

pub type AdapterError {
  UnsupportedStore(store_name: types.StoreName)
}

pub type BillStore {
  BillStore(
    exported_subjects: List(String),
    deleted_subjects: List(String),
    pseudonymised_subjects: List(String),
    retained_subjects: List(String),
    reviewed_subjects: List(String),
  )
}

pub fn empty() -> BillStore {
  BillStore(
    exported_subjects: [],
    deleted_subjects: [],
    pseudonymised_subjects: [],
    retained_subjects: [],
    reviewed_subjects: [],
  )
}

pub fn apply(
  store: BillStore,
  subject_ref: String,
  item: types.RequestItem,
) -> Result(#(BillStore, types.ExecutionResolution), AdapterError) {
  let types.RequestItem(
    store_name: store_name,
    action: action,
    note: _note,
    resolution: _resolution,
  ) = item

  case store_name {
    types.AccountingInvoice ->
      case action {
        types.ExportStore ->
          Ok(#(export_subject(store, subject_ref), types.Exported))
        types.DeleteStore ->
          Ok(#(delete_subject(store, subject_ref), types.Deleted))
        types.PseudonymiseStore ->
          Ok(#(pseudonymise_subject(store, subject_ref), types.Pseudonymised))
        types.RestrictStore ->
          Ok(#(retain_subject(store, subject_ref), types.Restricted))
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

fn export_subject(store: BillStore, subject_ref: String) -> BillStore {
  let BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  BillStore(
    exported_subjects: [subject_ref, ..exported_subjects],
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn delete_subject(store: BillStore, subject_ref: String) -> BillStore {
  let BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: [subject_ref, ..deleted_subjects],
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn pseudonymise_subject(store: BillStore, subject_ref: String) -> BillStore {
  let BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: [subject_ref, ..pseudonymised_subjects],
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  )
}

fn retain_subject(store: BillStore, subject_ref: String) -> BillStore {
  let BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: [subject_ref, ..retained_subjects],
    reviewed_subjects: reviewed_subjects,
  )
}

fn review_subject(store: BillStore, subject_ref: String) -> BillStore {
  let BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: reviewed_subjects,
  ) = store

  BillStore(
    exported_subjects: exported_subjects,
    deleted_subjects: deleted_subjects,
    pseudonymised_subjects: pseudonymised_subjects,
    retained_subjects: retained_subjects,
    reviewed_subjects: [subject_ref, ..reviewed_subjects],
  )
}
