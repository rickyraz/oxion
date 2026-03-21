# Collection Policy Contract Matrix (Phase A)

## 1. Tujuan

Matriks ini menyelaraskan kontrak antara:

- `collection-policy.schema.json` (machine contract)
- `collection-policy-ebnf.md` (evaluator semantics)
- `oxbill-spec.md` (domain type dan API)

---

## 2. Field and Structure Matrix

| Contract Item | Schema | EBNF | oxBill Spec | Status |
| --- | --- | --- | --- | --- |
| `stages[].id` | yes | yes | yes | aligned |
| `stages[].priority` | yes | yes | yes | aligned |
| `stages[].when` AST | yes | yes | yes | aligned |
| `stages[].stop_on_match` | yes | semantic | yes | aligned |
| `stages[].notification_template` | yes | metadata note | yes | aligned |
| `actions.apply_bandwidth_profile` | yes | n/a | yes | aligned |
| `actions.suspend_service` | yes | n/a | yes | aligned |
| `actions.restore_service` | yes | n/a | yes | aligned |
| `actions.send_notification` | yes | n/a | yes | aligned |
| `actions.emit_event` | yes | n/a | yes | aligned |
| `actions.set_operational_state` | yes | n/a | yes | aligned |
| `actions.run_plugin_hook` | yes | n/a | yes | aligned |

---

## 3. Lifecycle and Publish Contract

| Rule | Source | Status |
| --- | --- | --- |
| `draft -> simulated` allowed | `oxbill-spec.md` lifecycle table | aligned |
| `simulated -> published` allowed | `oxbill-spec.md` lifecycle table | aligned |
| `published -> archived` allowed | `oxbill-spec.md` lifecycle table | aligned |
| archived immutable | `oxbill-spec.md` lifecycle table | aligned |
| single active published per tenant | `oxbill-spec.md` unique index | aligned |

---

## 4. Determinism Rules

- Stage order: `priority` ascending.
- Tie-breaker: `stage.id` lexicographic.
- `stop_on_match=true` menghentikan evaluasi setelah stage match.

Referensi utama: `collection-policy-ebnf.md`.
