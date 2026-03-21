import gleam/list
import gleam/option
import oxion/platform/dsr/types

pub type WorkflowError {
  InvalidStatus(expected: types.RequestStatus, actual: types.RequestStatus)
  ItemNotFound(store_name: types.StoreName)
}

pub fn submit_request(
  id: String,
  tenant_id: String,
  subject_ref: String,
  request_type: types.RequestType,
  requested_by_actor: option.Option(String),
  reason: option.Option(String),
) -> types.DataSubjectRequest {
  types.DataSubjectRequest(
    id: id,
    tenant_id: tenant_id,
    subject_ref: subject_ref,
    request_type: request_type,
    status: types.Submitted,
    requested_by_actor: requested_by_actor,
    legal_hold: False,
    reason: reason,
    inventory: [],
    items: [],
  )
}

pub fn request_identity_verification(
  request: types.DataSubjectRequest,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  require_status(request, types.Submitted, fn(request_value) {
    let types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: _status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ) = request_value

    Ok(types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: types.IdentityVerificationPending,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ))
  })
}

pub fn verify_request(
  request: types.DataSubjectRequest,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  let types.DataSubjectRequest(
    id: id,
    tenant_id: tenant_id,
    subject_ref: subject_ref,
    request_type: request_type,
    status: status,
    requested_by_actor: requested_by_actor,
    legal_hold: legal_hold,
    reason: reason,
    inventory: inventory,
    items: items,
  ) = request

  case status {
    types.Submitted | types.IdentityVerificationPending ->
      Ok(types.DataSubjectRequest(
        id: id,
        tenant_id: tenant_id,
        subject_ref: subject_ref,
        request_type: request_type,
        status: types.Verified,
        requested_by_actor: requested_by_actor,
        legal_hold: legal_hold,
        reason: reason,
        inventory: inventory,
        items: items,
      ))

    _ ->
      Error(InvalidStatus(
        expected: types.IdentityVerificationPending,
        actual: status,
      ))
  }
}

pub fn apply_legal_hold(
  request: types.DataSubjectRequest,
  reason: String,
) -> types.DataSubjectRequest {
  let types.DataSubjectRequest(
    id: id,
    tenant_id: tenant_id,
    subject_ref: subject_ref,
    request_type: request_type,
    status: status,
    requested_by_actor: requested_by_actor,
    legal_hold: _legal_hold,
    reason: _existing_reason,
    inventory: inventory,
    items: items,
  ) = request

  types.DataSubjectRequest(
    id: id,
    tenant_id: tenant_id,
    subject_ref: subject_ref,
    request_type: request_type,
    status: status,
    requested_by_actor: requested_by_actor,
    legal_hold: True,
    reason: option.Some(reason),
    inventory: inventory,
    items: items,
  )
}

pub fn resolve_inventory(
  request: types.DataSubjectRequest,
  inventory: List(types.StoreInventoryItem),
) -> Result(types.DataSubjectRequest, WorkflowError) {
  require_status(request, types.Verified, fn(request_value) {
    let types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: _status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: _inventory,
      items: items,
    ) = request_value

    Ok(types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: types.InventoryResolved,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ))
  })
}

// Why: DSR planning must decide per store whether data is deleted,
// pseudonymised, retained, restricted, or excluded instead of pretending one
// destructive endpoint can settle every legal basis and retention rule.
pub fn plan_execution(
  request: types.DataSubjectRequest,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  require_status(request, types.InventoryResolved, fn(request_value) {
    let types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: _status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: _items,
    ) = request_value

    case legal_hold {
      True ->
        Ok(
          types.DataSubjectRequest(
            id: id,
            tenant_id: tenant_id,
            subject_ref: subject_ref,
            request_type: request_type,
            status: types.BlockedByLegalHold,
            requested_by_actor: requested_by_actor,
            legal_hold: legal_hold,
            reason: reason,
            inventory: inventory,
            items: [],
          ),
        )

      False ->
        Ok(types.DataSubjectRequest(
          id: id,
          tenant_id: tenant_id,
          subject_ref: subject_ref,
          request_type: request_type,
          status: types.ExecutionPlanned,
          requested_by_actor: requested_by_actor,
          legal_hold: legal_hold,
          reason: reason,
          inventory: inventory,
          items: list.map(inventory, fn(item) { plan_item(request_type, item) }),
        ))
    }
  })
}

pub fn start_execution(
  request: types.DataSubjectRequest,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  require_status(request, types.ExecutionPlanned, fn(request_value) {
    let types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: _status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ) = request_value

    Ok(types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: types.InProgress,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ))
  })
}

pub fn record_resolution(
  request: types.DataSubjectRequest,
  store_name: types.StoreName,
  resolution: types.ExecutionResolution,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  require_status(request, types.InProgress, fn(request_value) {
    let types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: _status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ) = request_value

    case update_item_resolution(items, store_name, resolution, []) {
      Ok(updated_items) ->
        Ok(types.DataSubjectRequest(
          id: id,
          tenant_id: tenant_id,
          subject_ref: subject_ref,
          request_type: request_type,
          status: types.InProgress,
          requested_by_actor: requested_by_actor,
          legal_hold: legal_hold,
          reason: reason,
          inventory: inventory,
          items: updated_items,
        ))

      Error(error) -> Error(error)
    }
  })
}

pub fn finish_execution(
  request: types.DataSubjectRequest,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  require_status(request, types.InProgress, fn(request_value) {
    let types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: _status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ) = request_value
    let status = final_status(items)

    Ok(types.DataSubjectRequest(
      id: id,
      tenant_id: tenant_id,
      subject_ref: subject_ref,
      request_type: request_type,
      status: status,
      requested_by_actor: requested_by_actor,
      legal_hold: legal_hold,
      reason: reason,
      inventory: inventory,
      items: items,
    ))
  })
}

pub fn cancel_request(
  request: types.DataSubjectRequest,
) -> Result(types.DataSubjectRequest, WorkflowError) {
  let types.DataSubjectRequest(
    id: id,
    tenant_id: tenant_id,
    subject_ref: subject_ref,
    request_type: request_type,
    status: status,
    requested_by_actor: requested_by_actor,
    legal_hold: legal_hold,
    reason: reason,
    inventory: inventory,
    items: items,
  ) = request

  case status {
    types.Completed | types.PartiallyCompleted ->
      Error(InvalidStatus(expected: types.Submitted, actual: status))
    _ ->
      Ok(types.DataSubjectRequest(
        id: id,
        tenant_id: tenant_id,
        subject_ref: subject_ref,
        request_type: request_type,
        status: types.Cancelled,
        requested_by_actor: requested_by_actor,
        legal_hold: legal_hold,
        reason: reason,
        inventory: inventory,
        items: items,
      ))
  }
}

fn require_status(
  request: types.DataSubjectRequest,
  expected: types.RequestStatus,
  next: fn(types.DataSubjectRequest) ->
    Result(types.DataSubjectRequest, WorkflowError),
) -> Result(types.DataSubjectRequest, WorkflowError) {
  let types.DataSubjectRequest(status: status, ..) = request

  case status == expected {
    True -> next(request)
    False -> Error(InvalidStatus(expected: expected, actual: status))
  }
}

fn plan_item(
  request_type: types.RequestType,
  inventory_item: types.StoreInventoryItem,
) -> types.RequestItem {
  let types.StoreInventoryItem(
    store_name: store_name,
    has_direct_personal_data: has_direct_personal_data,
    has_legal_obligation: has_legal_obligation,
    supports_portability: supports_portability,
    relevant_to_subject: relevant_to_subject,
  ) = inventory_item

  case request_type {
    types.Access ->
      case store_name {
        types.AuditPrivateContext ->
          request_item(
            store_name,
            types.NoAction,
            option.Some("excluded_from_default_export"),
          )
        types.Backups ->
          request_item(
            store_name,
            types.NoAction,
            option.Some("backup_restore_path_only"),
          )
        _ ->
          case relevant_to_subject {
            True -> request_item(store_name, types.ExportStore, option.None)
            False ->
              request_item(
                store_name,
                types.NoAction,
                option.Some("subject_not_present"),
              )
          }
      }

    types.Erasure ->
      case store_name {
        types.SubscriberProfile ->
          case has_direct_personal_data {
            True -> request_item(store_name, types.DeleteStore, option.None)
            False ->
              request_item(
                store_name,
                types.NoAction,
                option.Some("no_direct_personal_data"),
              )
          }
        types.ActiveSessions ->
          request_item(store_name, types.DeleteStore, option.None)
        types.AccountingInvoice ->
          case has_legal_obligation {
            True ->
              request_item(
                store_name,
                types.PseudonymiseStore,
                option.Some("retained_under_legal_obligation"),
              )
            False -> request_item(store_name, types.DeleteStore, option.None)
          }
        types.AuditLog ->
          request_item(
            store_name,
            types.RetainStore,
            option.Some("redacted_long_audit"),
          )
        types.AuditPrivateContext ->
          request_item(
            store_name,
            types.CryptoShredStore,
            option.Some("short_retention_sensitive_context"),
          )
        types.ConsentRecords ->
          request_item(
            store_name,
            types.RetainStore,
            option.Some("minimal_evidence_retained"),
          )
        types.Backups ->
          request_item(
            store_name,
            types.RetainStore,
            option.Some("age_out_only"),
          )
      }

    types.Restriction ->
      case store_name {
        types.Backups ->
          request_item(
            store_name,
            types.RetainStore,
            option.Some("immutable_backup_age_out"),
          )
        _ -> request_item(store_name, types.RestrictStore, option.None)
      }

    types.Portability ->
      case supports_portability && relevant_to_subject {
        True -> request_item(store_name, types.ExportStore, option.None)
        False ->
          request_item(
            store_name,
            types.NoAction,
            option.Some("not_portable_by_default"),
          )
      }

    types.Rectification ->
      case store_name {
        types.SubscriberProfile | types.AccountingInvoice | types.ConsentRecords ->
          request_item(
            store_name,
            types.ReviewStore,
            option.Some("manual_rectification_required"),
          )
        types.AuditLog | types.Backups ->
          request_item(
            store_name,
            types.RetainStore,
            option.Some("historical_record_not_mutated"),
          )
        _ ->
          request_item(
            store_name,
            types.NoAction,
            option.Some("no_rectification_step"),
          )
      }

    types.Objection ->
      case store_name {
        types.AuditLog | types.Backups ->
          request_item(
            store_name,
            types.RetainStore,
            option.Some("historical_or_backup_record"),
          )
        types.AccountingInvoice ->
          case has_legal_obligation {
            True ->
              request_item(
                store_name,
                types.RetainStore,
                option.Some("legal_obligation_overrides_objection"),
              )
            False ->
              request_item(
                store_name,
                types.ReviewStore,
                option.Some("legitimate_interest_review"),
              )
          }
        _ ->
          request_item(
            store_name,
            types.ReviewStore,
            option.Some("objection_requires_controller_review"),
          )
      }
  }
}

fn request_item(
  store_name: types.StoreName,
  action: types.PlannedAction,
  note: option.Option(String),
) -> types.RequestItem {
  types.RequestItem(
    store_name: store_name,
    action: action,
    note: note,
    resolution: option.None,
  )
}

fn update_item_resolution(
  remaining: List(types.RequestItem),
  store_name: types.StoreName,
  resolution: types.ExecutionResolution,
  acc: List(types.RequestItem),
) -> Result(List(types.RequestItem), WorkflowError) {
  case remaining {
    [] -> Error(ItemNotFound(store_name: store_name))
    [item, ..rest] -> {
      let types.RequestItem(
        store_name: current_store,
        action: action,
        note: note,
        resolution: _existing_resolution,
      ) = item

      case current_store == store_name {
        True ->
          Ok(list.append(
            list.reverse([
              types.RequestItem(
                store_name: current_store,
                action: action,
                note: note,
                resolution: option.Some(resolution),
              ),
              ..acc
            ]),
            rest,
          ))

        False ->
          update_item_resolution(rest, store_name, resolution, [item, ..acc])
      }
    }
  }
}

fn final_status(items: List(types.RequestItem)) -> types.RequestStatus {
  case types.all_terminal(items) {
    False -> types.PartiallyCompleted
    True ->
      case list.any(items, fn(item) { item_failed(item) }) {
        True -> types.PartiallyCompleted
        False -> types.Completed
      }
  }
}

fn item_failed(item: types.RequestItem) -> Bool {
  let types.RequestItem(
    store_name: _store_name,
    action: _action,
    note: _note,
    resolution: resolution,
  ) = item

  case resolution {
    option.Some(types.Failed(_)) -> True
    _ -> False
  }
}
