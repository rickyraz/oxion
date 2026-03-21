# Oxion Testing Strategy (Deterministic + Integration)

## 1. Tujuan

Dokumen ini merangkum mekanisme testing untuk arsitektur Oxion (policy-driven collection, RADIUS/NAS/CoA, dan orchestration) agar hasil konsisten lintas runtime.

---

## 2. Test Layers

## A. Contract Tests

- Validasi policy terhadap `collection-policy.schema.json`.
- Conformance evaluator terhadap `collection-policy-ebnf.md`.
- Reject policy invalid sebelum publish.

## B. Deterministic Engine Tests

- Input sama (`policy + context`) harus menghasilkan output stage/action yang sama.
- Golden snapshot untuk `evaluate(policy, context)`.
- Tie-breaker stabil (`priority`, lalu `stage.id`).

## C. State Machine Tests

- Service state: `normal -> throttled_due_overdue -> suspended_due_overdue -> normal`.
- Policy lifecycle: `draft -> simulated -> published -> archived`.
- Single active published policy per tenant.

## D. Idempotency Tests

- Event overdue duplikat tidak menghasilkan CoA/action duplikat.
- `send_coa_if_needed` skip saat target profile sudah aktif.
- Enforcement log menyimpan `action_fingerprint` unik.

## E. Integration Tests

- `oxBill -> oxCore -> oxRADIUS` path untuk throttle/suspend/restore.
- CoA ACK/NAK handling + retry terbatas + alert.
- Payment paid -> restore profile + unsuspend.

## F. Vendor Adapter Tests

- Mapping intent internal ke Cisco/Juniper/vBNG profile.
- Fallback attrs jika attr vendor unsupported.
- Normalize error reason ke internal error code.

## G. Packet-Level/UAT Tests

- Access-Request/Accept, Accounting Start/Interim/Stop.
- CoA throttle/suspend/restore packet validation.
- Boundary `radius_only`: OLT tidak berubah.

---

## 3. Deterministic Simulation Tests (Wajib)

## Simulator 1: Policy Outcome Simulator

- Input: policy + context subscriber + `days_past_due`.
- Output: matched stage + action list + reason.

## Simulator 2: Timeline Simulator

- Simulasi hari 0..N untuk overdue progression.
- Uji partial payment dan multiple overdue invoices.

## Simulator 3: Failure/Retry Simulator

- CoA timeout, CoA-NAK, duplicate scheduler run, duplicate webhook.

## Simulator 4: Timezone Simulator

- Validasi evaluasi tenant timezone berbeda pada batas hari.

---

## 4. Invariants (Test Oracle)

- No hardcoded day/speed di core.
- Published policy harus sudah simulated.
- Archived policy immutable.
- Single active published policy per tenant.
- Duplicate event tidak boleh menghasilkan duplicate enforcement.
- Restore tidak boleh terjadi jika masih ada overdue aktif lain.

---

## 5. Urutan Implementasi Test (Fastest Safe Path)

1. Contract + EBNF conformance tests.
2. Deterministic evaluator + golden snapshots.
3. Lifecycle + idempotency tests.
4. Integration CoA ACK/NAK tests.
5. Vendor adapter mapping tests.
6. Packet-level lab/UAT sign-off.
