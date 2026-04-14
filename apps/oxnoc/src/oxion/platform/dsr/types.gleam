import gleam/list
import gleam/option

pub type RequestType {
  Access
  Erasure
  Restriction
  Rectification
  Objection
  Portability
}

pub type RequestStatus {
  Submitted
  IdentityVerificationPending
  Verified
  InventoryResolved
  ExecutionPlanned
  InProgress
  Completed
  Rejected
  BlockedByLegalHold
  PartiallyCompleted
  Cancelled
}

pub type StoreName {
  SubscriberProfile
  ActiveSessions
  AccountingInvoice
  AuditLog
  AuditPrivateContext
  ConsentRecords
  Backups
}

pub type PlannedAction {
  ExportStore
  DeleteStore
  PseudonymiseStore
  RestrictStore
  RetainStore
  CryptoShredStore
  ReviewStore
  NoAction
}

pub type ExecutionResolution {
  Exported
  Deleted
  Pseudonymised
  Restricted
  Retained
  CryptoShredded
  Reviewed
  NotApplicable
  Failed(reason: String)
}

pub type StoreInventoryItem {
  StoreInventoryItem(
    store_name: StoreName,
    has_direct_personal_data: Bool,
    has_legal_obligation: Bool,
    supports_portability: Bool,
    relevant_to_subject: Bool,
  )
}

pub type RequestItem {
  RequestItem(
    store_name: StoreName,
    action: PlannedAction,
    note: option.Option(String),
    resolution: option.Option(ExecutionResolution),
  )
}

pub type DataSubjectRequest {
  DataSubjectRequest(
    id: String,
    tenant_id: String,
    subject_ref: String,
    request_type: RequestType,
    status: RequestStatus,
    requested_by_actor: option.Option(String),
    legal_hold: Bool,
    reason: option.Option(String),
    inventory: List(StoreInventoryItem),
    items: List(RequestItem),
  )
}

pub fn all_terminal(items: List(RequestItem)) -> Bool {
  case list.all(items, fn(item) { item_terminal(item) }) {
    True -> True
    False -> False
  }
}

fn item_terminal(item: RequestItem) -> Bool {
  let RequestItem(
    store_name: _store_name,
    action: _action,
    note: _note,
    resolution: resolution,
  ) = item

  case resolution {
    option.Some(_) -> True
    option.None -> False
  }
}
