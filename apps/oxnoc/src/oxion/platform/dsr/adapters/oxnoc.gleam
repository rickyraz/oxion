import oxion/platform/dsr/types

pub type AdapterError {
  UnsupportedStore(store_name: types.StoreName)
}

pub type NocStore {
  NocStore(
    exported_audit_subjects: List(String),
    retained_audit_subjects: List(String),
    shredded_private_context_subjects: List(String),
    restricted_private_context_subjects: List(String),
  )
}

pub fn empty() -> NocStore {
  NocStore(
    exported_audit_subjects: [],
    retained_audit_subjects: [],
    shredded_private_context_subjects: [],
    restricted_private_context_subjects: [],
  )
}

pub fn apply(
  store: NocStore,
  subject_ref: String,
  item: types.RequestItem,
) -> Result(#(NocStore, types.ExecutionResolution), AdapterError) {
  let types.RequestItem(
    store_name: store_name,
    action: action,
    note: _note,
    resolution: _resolution,
  ) = item

  case store_name {
    types.AuditLog ->
      case action {
        types.ExportStore ->
          Ok(#(export_audit_subject(store, subject_ref), types.Exported))
        types.RetainStore ->
          Ok(#(retain_audit_subject(store, subject_ref), types.Retained))
        types.RestrictStore ->
          Ok(#(retain_audit_subject(store, subject_ref), types.Restricted))
        types.NoAction -> Ok(#(store, types.NotApplicable))
        _ -> Ok(#(store, types.NotApplicable))
      }

    types.AuditPrivateContext ->
      case action {
        types.CryptoShredStore ->
          Ok(#(shred_private_context(store, subject_ref), types.CryptoShredded))
        types.RestrictStore ->
          Ok(#(restrict_private_context(store, subject_ref), types.Restricted))
        types.NoAction -> Ok(#(store, types.NotApplicable))
        _ -> Ok(#(store, types.NotApplicable))
      }

    _ -> Error(UnsupportedStore(store_name: store_name))
  }
}

fn export_audit_subject(store: NocStore, subject_ref: String) -> NocStore {
  let NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: restricted_private_context_subjects,
  ) = store

  NocStore(
    exported_audit_subjects: [subject_ref, ..exported_audit_subjects],
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: restricted_private_context_subjects,
  )
}

fn retain_audit_subject(store: NocStore, subject_ref: String) -> NocStore {
  let NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: restricted_private_context_subjects,
  ) = store

  NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: [subject_ref, ..retained_audit_subjects],
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: restricted_private_context_subjects,
  )
}

fn shred_private_context(store: NocStore, subject_ref: String) -> NocStore {
  let NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: restricted_private_context_subjects,
  ) = store

  NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: [
      subject_ref,
      ..shredded_private_context_subjects
    ],
    restricted_private_context_subjects: restricted_private_context_subjects,
  )
}

fn restrict_private_context(store: NocStore, subject_ref: String) -> NocStore {
  let NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: restricted_private_context_subjects,
  ) = store

  NocStore(
    exported_audit_subjects: exported_audit_subjects,
    retained_audit_subjects: retained_audit_subjects,
    shredded_private_context_subjects: shredded_private_context_subjects,
    restricted_private_context_subjects: [
      subject_ref,
      ..restricted_private_context_subjects
    ],
  )
}
