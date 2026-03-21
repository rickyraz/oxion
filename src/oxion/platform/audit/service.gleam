import gleam/option
import oxion/orchestration/collection/audit as collection_audit
import oxion/platform/audit/adapter
import oxion/platform/audit/persistence
import oxion/platform/audit/types

pub fn persist_collection_entry(
  store: persistence.AuditStore,
  entry: collection_audit.AuditEntry,
  runtime_context: option.Option(types.RuntimeAuditContext),
) -> Result(persistence.AuditStore, persistence.PersistenceError) {
  let envelope = adapter.from_collection_entry(entry, runtime_context)

  persistence.persist(store, envelope)
}
