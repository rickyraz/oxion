import gleam/list
import gleam/option
import oxion/platform/dsr/types
import oxion/platform/dsr/workflow

pub fn dsr_workflow_plans_erasure_with_store_specific_actions_test() {
  let request =
    workflow.submit_request(
      "dsr_1",
      "tenant_a",
      "sub_1",
      types.Erasure,
      option.Some("ops_123"),
      option.Some("subscriber_requested_erasure"),
    )
    |> workflow.request_identity_verification
    |> unwrap
    |> workflow.verify_request
    |> unwrap
    |> workflow.resolve_inventory(sample_inventory())
    |> unwrap
    |> workflow.plan_execution
    |> unwrap

  assert request.status == types.ExecutionPlanned
  assert list.length(request.items) == 7
  assert request.items
    == [
      types.RequestItem(
        store_name: types.SubscriberProfile,
        action: types.DeleteStore,
        note: option.None,
        resolution: option.None,
      ),
      types.RequestItem(
        store_name: types.ActiveSessions,
        action: types.DeleteStore,
        note: option.None,
        resolution: option.None,
      ),
      types.RequestItem(
        store_name: types.AccountingInvoice,
        action: types.PseudonymiseStore,
        note: option.Some("retained_under_legal_obligation"),
        resolution: option.None,
      ),
      types.RequestItem(
        store_name: types.AuditLog,
        action: types.RetainStore,
        note: option.Some("redacted_long_audit"),
        resolution: option.None,
      ),
      types.RequestItem(
        store_name: types.AuditPrivateContext,
        action: types.CryptoShredStore,
        note: option.Some("short_retention_sensitive_context"),
        resolution: option.None,
      ),
      types.RequestItem(
        store_name: types.ConsentRecords,
        action: types.RetainStore,
        note: option.Some("minimal_evidence_retained"),
        resolution: option.None,
      ),
      types.RequestItem(
        store_name: types.Backups,
        action: types.RetainStore,
        note: option.Some("age_out_only"),
        resolution: option.None,
      ),
    ]
}

pub fn dsr_workflow_blocks_execution_when_legal_hold_is_active_test() {
  let request =
    workflow.submit_request(
      "dsr_2",
      "tenant_a",
      "sub_1",
      types.Erasure,
      option.Some("ops_123"),
      option.Some("chargeback_open"),
    )
    |> workflow.request_identity_verification
    |> unwrap
    |> workflow.verify_request
    |> unwrap
    |> workflow.resolve_inventory(sample_inventory())
    |> unwrap
    |> workflow.apply_legal_hold("chargeback_open")
    |> workflow.plan_execution
    |> unwrap

  assert request.status == types.BlockedByLegalHold
  assert request.legal_hold == True
  assert request.reason == option.Some("chargeback_open")
  assert request.items == []
}

pub fn dsr_workflow_completes_when_all_items_are_resolved_test() {
  let request =
    planned_request(types.Access)
    |> workflow.start_execution
    |> unwrap
    |> workflow.record_resolution(types.SubscriberProfile, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.ActiveSessions, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.AccountingInvoice, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.AuditLog, types.Exported)
    |> unwrap
    |> workflow.record_resolution(
      types.AuditPrivateContext,
      types.NotApplicable,
    )
    |> unwrap
    |> workflow.record_resolution(types.ConsentRecords, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.Backups, types.NotApplicable)
    |> unwrap
    |> workflow.finish_execution
    |> unwrap

  assert request.status == types.Completed
}

pub fn dsr_workflow_marks_partial_completion_on_failed_store_test() {
  let request =
    planned_request(types.Portability)
    |> workflow.start_execution
    |> unwrap
    |> workflow.record_resolution(types.SubscriberProfile, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.ActiveSessions, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.AccountingInvoice, types.Exported)
    |> unwrap
    |> workflow.record_resolution(types.AuditLog, types.NotApplicable)
    |> unwrap
    |> workflow.record_resolution(
      types.AuditPrivateContext,
      types.NotApplicable,
    )
    |> unwrap
    |> workflow.record_resolution(
      types.ConsentRecords,
      types.Failed(reason: "provider_timeout"),
    )
    |> unwrap
    |> workflow.record_resolution(types.Backups, types.NotApplicable)
    |> unwrap
    |> workflow.finish_execution
    |> unwrap

  assert request.status == types.PartiallyCompleted
}

fn planned_request(request_type: types.RequestType) -> types.DataSubjectRequest {
  workflow.submit_request(
    "dsr_planned",
    "tenant_a",
    "sub_1",
    request_type,
    option.Some("ops_123"),
    option.None,
  )
  |> workflow.request_identity_verification
  |> unwrap
  |> workflow.verify_request
  |> unwrap
  |> workflow.resolve_inventory(sample_inventory())
  |> unwrap
  |> workflow.plan_execution
  |> unwrap
}

fn sample_inventory() -> List(types.StoreInventoryItem) {
  [
    types.StoreInventoryItem(
      store_name: types.SubscriberProfile,
      has_direct_personal_data: True,
      has_legal_obligation: False,
      supports_portability: True,
      relevant_to_subject: True,
    ),
    types.StoreInventoryItem(
      store_name: types.ActiveSessions,
      has_direct_personal_data: True,
      has_legal_obligation: False,
      supports_portability: True,
      relevant_to_subject: True,
    ),
    types.StoreInventoryItem(
      store_name: types.AccountingInvoice,
      has_direct_personal_data: True,
      has_legal_obligation: True,
      supports_portability: True,
      relevant_to_subject: True,
    ),
    types.StoreInventoryItem(
      store_name: types.AuditLog,
      has_direct_personal_data: False,
      has_legal_obligation: True,
      supports_portability: True,
      relevant_to_subject: True,
    ),
    types.StoreInventoryItem(
      store_name: types.AuditPrivateContext,
      has_direct_personal_data: True,
      has_legal_obligation: False,
      supports_portability: False,
      relevant_to_subject: True,
    ),
    types.StoreInventoryItem(
      store_name: types.ConsentRecords,
      has_direct_personal_data: True,
      has_legal_obligation: True,
      supports_portability: True,
      relevant_to_subject: True,
    ),
    types.StoreInventoryItem(
      store_name: types.Backups,
      has_direct_personal_data: True,
      has_legal_obligation: True,
      supports_portability: False,
      relevant_to_subject: True,
    ),
  ]
}

fn unwrap(result: Result(a, workflow.WorkflowError)) -> a {
  case result {
    Ok(value) -> value
    Error(_) -> panic
  }
}
