import oxion/platform/dsr/adapters/oxbill
import oxion/platform/dsr/adapters/oxcore
import oxion/platform/dsr/adapters/oxnoc
import oxion/platform/dsr/adapters/oxradius
import oxion/platform/dsr/types
import oxion/platform/dsr/workflow

pub type AdapterBundle {
  AdapterBundle(
    oxradius: oxradius.RadiusStore,
    oxbill: oxbill.BillStore,
    oxcore: oxcore.CoreStore,
    oxnoc: oxnoc.NocStore,
  )
}

pub type ExecutionError {
  WorkflowFailure(error: workflow.WorkflowError)
  OxradiusFailure(error: oxradius.AdapterError)
  OxbillFailure(error: oxbill.AdapterError)
  OxcoreFailure(error: oxcore.AdapterError)
  OxnocFailure(error: oxnoc.AdapterError)
}

pub fn empty_bundle() -> AdapterBundle {
  AdapterBundle(
    oxradius: oxradius.empty(),
    oxbill: oxbill.empty(),
    oxcore: oxcore.empty(),
    oxnoc: oxnoc.empty(),
  )
}

// Why: the workflow already decided per-store actions, so executor responsibility
// is only to route each request item to the bounded-context adapter that owns it
// and feed the resulting resolution back into the DSR state machine.
pub fn execute(
  request: types.DataSubjectRequest,
  bundle: AdapterBundle,
) -> Result(#(types.DataSubjectRequest, AdapterBundle), ExecutionError) {
  case workflow.start_execution(request) {
    Ok(in_progress) ->
      execute_items(
        in_progress,
        in_progress.subject_ref,
        in_progress.items,
        bundle,
      )

    Error(error) -> Error(WorkflowFailure(error: error))
  }
}

fn execute_items(
  request: types.DataSubjectRequest,
  subject_ref: String,
  remaining: List(types.RequestItem),
  bundle: AdapterBundle,
) -> Result(#(types.DataSubjectRequest, AdapterBundle), ExecutionError) {
  case remaining {
    [] ->
      case workflow.finish_execution(request) {
        Ok(completed) -> Ok(#(completed, bundle))
        Error(error) -> Error(WorkflowFailure(error: error))
      }

    [item, ..rest] -> {
      let types.RequestItem(
        store_name: store_name,
        action: _action,
        note: _note,
        resolution: _resolution,
      ) = item

      case apply_item(bundle, subject_ref, item) {
        Ok(#(updated_bundle, resolution)) ->
          case workflow.record_resolution(request, store_name, resolution) {
            Ok(updated_request) ->
              execute_items(updated_request, subject_ref, rest, updated_bundle)
            Error(error) -> Error(WorkflowFailure(error: error))
          }

        Error(error) -> Error(error)
      }
    }
  }
}

fn apply_item(
  bundle: AdapterBundle,
  subject_ref: String,
  item: types.RequestItem,
) -> Result(#(AdapterBundle, types.ExecutionResolution), ExecutionError) {
  let types.RequestItem(
    store_name: store_name,
    action: _action,
    note: _note,
    resolution: _resolution,
  ) = item
  let AdapterBundle(
    oxradius: radius_store,
    oxbill: bill_store,
    oxcore: core_store,
    oxnoc: noc_store,
  ) = bundle

  case store_name {
    types.SubscriberProfile | types.ActiveSessions ->
      case oxradius.apply(radius_store, subject_ref, item) {
        Ok(#(updated_store, resolution)) ->
          Ok(#(
            AdapterBundle(
              oxradius: updated_store,
              oxbill: bill_store,
              oxcore: core_store,
              oxnoc: noc_store,
            ),
            resolution,
          ))
        Error(error) -> Error(OxradiusFailure(error: error))
      }

    types.AccountingInvoice ->
      case oxbill.apply(bill_store, subject_ref, item) {
        Ok(#(updated_store, resolution)) ->
          Ok(#(
            AdapterBundle(
              oxradius: radius_store,
              oxbill: updated_store,
              oxcore: core_store,
              oxnoc: noc_store,
            ),
            resolution,
          ))
        Error(error) -> Error(OxbillFailure(error: error))
      }

    types.ConsentRecords | types.Backups ->
      case oxcore.apply(core_store, subject_ref, item) {
        Ok(#(updated_store, resolution)) ->
          Ok(#(
            AdapterBundle(
              oxradius: radius_store,
              oxbill: bill_store,
              oxcore: updated_store,
              oxnoc: noc_store,
            ),
            resolution,
          ))
        Error(error) -> Error(OxcoreFailure(error: error))
      }

    types.AuditLog | types.AuditPrivateContext ->
      case oxnoc.apply(noc_store, subject_ref, item) {
        Ok(#(updated_store, resolution)) ->
          Ok(#(
            AdapterBundle(
              oxradius: radius_store,
              oxbill: bill_store,
              oxcore: core_store,
              oxnoc: updated_store,
            ),
            resolution,
          ))
        Error(error) -> Error(OxnocFailure(error: error))
      }
  }
}
