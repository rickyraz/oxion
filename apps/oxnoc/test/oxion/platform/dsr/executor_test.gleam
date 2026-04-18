import gleam/option
import oxion/platform/dsr/adapters/oxbill
import oxion/platform/dsr/adapters/oxcore
import oxion/platform/dsr/adapters/oxnoc
import oxion/platform/dsr/adapters/oxradius
import oxion/platform/dsr/executor
import oxion/platform/dsr/types
import oxion/platform/dsr/workflow

pub fn dsr_executor_routes_erasure_to_all_bounded_context_adapters_test() {
  let request = planned_request(types.Erasure)
  let #(completed, bundle) = case
    executor.execute(request, executor.empty_bundle())
  {
    Ok(result) -> result
    Error(_) -> panic
  }

  assert completed.status == types.Completed
  assert bundle.oxradius
    == oxradius.RadiusStore(
      exported_subjects: [],
      deleted_profiles: ["sub_1"],
      deleted_sessions: ["sub_1"],
      restricted_subjects: [],
      reviewed_subjects: [],
    )
  assert bundle.oxbill
    == oxbill.BillStore(
      exported_subjects: [],
      deleted_subjects: [],
      pseudonymised_subjects: ["sub_1"],
      retained_subjects: [],
      reviewed_subjects: [],
    )
  assert bundle.oxcore
    == oxcore.CoreStore(
      exported_subjects: [],
      restricted_subjects: [],
      retained_subjects: ["sub_1", "sub_1"],
      reviewed_subjects: [],
    )
  assert bundle.oxnoc
    == oxnoc.NocStore(
      exported_audit_subjects: [],
      retained_audit_subjects: ["sub_1"],
      shredded_private_context_subjects: ["sub_1"],
      restricted_private_context_subjects: [],
    )
}

pub fn dsr_executor_routes_access_exports_and_not_applicable_steps_test() {
  let request = planned_request(types.Access)
  let #(completed, bundle) = case
    executor.execute(request, executor.empty_bundle())
  {
    Ok(result) -> result
    Error(_) -> panic
  }

  assert completed.status == types.Completed
  assert bundle.oxradius
    == oxradius.RadiusStore(
      exported_subjects: ["sub_1", "sub_1"],
      deleted_profiles: [],
      deleted_sessions: [],
      restricted_subjects: [],
      reviewed_subjects: [],
    )
  assert bundle.oxbill
    == oxbill.BillStore(
      exported_subjects: ["sub_1"],
      deleted_subjects: [],
      pseudonymised_subjects: [],
      retained_subjects: [],
      reviewed_subjects: [],
    )
  assert bundle.oxcore
    == oxcore.CoreStore(
      exported_subjects: ["sub_1"],
      restricted_subjects: [],
      retained_subjects: [],
      reviewed_subjects: [],
    )
  assert bundle.oxnoc
    == oxnoc.NocStore(
      exported_audit_subjects: ["sub_1"],
      retained_audit_subjects: [],
      shredded_private_context_subjects: [],
      restricted_private_context_subjects: [],
    )
}

pub fn dsr_executor_rerun_is_idempotent_by_rejecting_completed_request_test() {
  let request = planned_request(types.Erasure)
  let #(completed, first_bundle) = case
    executor.execute(request, executor.empty_bundle())
  {
    Ok(result) -> result
    Error(_) -> panic
  }

  assert completed.status == types.Completed

  assert executor.execute(completed, first_bundle)
    == Error(
      executor.WorkflowFailure(error: workflow.InvalidStatus(
        expected: types.ExecutionPlanned,
        actual: types.Completed,
      )),
    )
}

fn planned_request(request_type: types.RequestType) -> types.DataSubjectRequest {
  workflow.submit_request(
    "dsr_executor",
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
