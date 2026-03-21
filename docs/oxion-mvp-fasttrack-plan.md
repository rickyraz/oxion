# Oxion MVP Fast-Track Plan (Dependency-Driven)

## 1. Tujuan

Dokumen ini mendefinisikan jalur implementasi **tercepat berbasis dependency** untuk MVP collection enforcement Oxion.

Makna "tercepat":

- Bukan target tanggal tetap.
- Bukan kerja paralel sebanyak mungkin.
- Tetapi urutan kerja dengan **rework paling kecil**, **blocking paling sedikit**, dan **gate quality paling jelas**.

---

## 2. Prinsip Eksekusi (Orthogonal + Unix)

- Setiap modul melakukan satu tanggung jawab utama.
- Policy dipisah dari mechanism (policy engine tidak kirim CoA langsung).
- Gateway hanya routing/middleware, domain logic berada di module domain.
- Semua action harus idempotent dan traceable (audit log + fingerprint).
- Seluruh behavior kritikal harus deterministic lintas implementasi bahasa.

---

## 3. Strict Scope MVP (Tidak Bisa Ditawar)

MVP dinyatakan lulus hanya jika semua poin berikut pass end-to-end:

1. **Policy collection full data-driven**
   - Rule didefinisikan dari JSON policy builder.
   - Mengikuti `collection-policy.schema.json` dan `collection-policy-ebnf.md`.
   - Tidak ada hardcoded day/speed di core.

2. **Overdue enforcement radius-only + idempotent**
   - Throttle/suspend dijalankan via AAA/RADIUS path.
   - OLT tidak berubah pada default overdue flow.
   - Tidak ada CoA berulang jika profile sudah sama.

3. **Stage notification + payment link + auto-restore**
   - Notifikasi dipicu oleh stage policy.
   - Payment link mode static/signed tersedia.
   - Saat invoice paid, service kembali normal otomatis.

---

## 4. Critical Path (Wajib Berurutan)

1. Contract freeze
2. Evaluator core
3. Scheduler + dispatcher
4. RADIUS execution guard
5. Restore path
6. UI builder publish/simulate
7. UAT + hardening

Semua item di luar jalur ini boleh paralel hanya jika tidak mengubah kontrak inti.

---

## 5. Phase Detail per Module/Submodule

## Phase A — Contract and Determinism Baseline

### A1. Module: `oxBill.policy_contract`

- **Submodule:** schema contract
  - `collection-policy.schema.json`
  - field/action compatibility matrix
- **Submodule:** grammar/semantic contract
  - `collection-policy-ebnf.md`
  - operator/field/type rules
- **Submodule:** versioning contract
  - `policy_version`, `draft/simulated/published`

Entry criteria:

- Dokumen schema/EBNF tersedia dan konsisten.

Exit criteria:

- Tidak ada ambigu antara schema vs EBNF.
- Conformance checklist disepakati tim BE/FE.

Artefak phase:

- `collection-policy.schema.json`
- `collection-policy-ebnf.md`
- `collection-policy-contract-matrix.md`
- `conformance-checklist/phase-a-conformance-checklist.md`

---

## Phase B — Policy Engine Core

### B1. Module: `oxBill.policy_validator`

- **Submodule:** JSON schema validator
- **Submodule:** semantic validator
  - validasi operator terhadap field type
  - validasi `between` range

### B2. Module: `oxBill.policy_evaluator`

- **Submodule:** condition AST evaluator (`all/any/rule`)
- **Submodule:** stage ordering (`priority`, tie-breaker `stage.id`)
- **Submodule:** stop behavior (`stop_on_match`)

### B3. Module: `oxBill.policy_simulator`

- **Submodule:** simulation API for overdue ranges
- **Submodule:** explain output (matched stage + actions + reason)

Entry criteria:

- Phase A complete.

Exit criteria:

- Input context yang sama selalu menghasilkan output sama.
- Error normatif keluar dengan code/path/reason konsisten.

Artefak phase:

- `src/oxion/policy/types.gleam`
- `src/oxion/policy/validator.gleam`
- `src/oxion/policy/evaluator.gleam`
- `src/oxion/policy/simulator.gleam`
- `conformance-checklist/phase-b-conformance-checklist.md`

---

## Phase C — Enforcement Runtime and Idempotency

### C1. Module: `oxBill.collection_scheduler`

- **Submodule:** tenant timezone runner
- **Submodule:** overdue candidate selector
- **Submodule:** queue dispatcher

### C2. Module: `oxBill.action_dispatcher`

- **Submodule:** action-to-command mapper
  - `apply_bandwidth_profile`
  - `suspend_service`
  - `restore_service`
  - `send_notification`
  - `emit_event`

### C3. Module: `oxBill.idempotency_guard`

- **Submodule:** `action_fingerprint` generator
- **Submodule:** dedupe writer (`collection_enforcement_log`)
- **Submodule:** retry-safe executor

Entry criteria:

- Phase B complete.

Exit criteria:

- Scheduler rerun tidak menimbulkan duplicate action.
- Semua action memiliki audit trail dan fingerprint.

Artefak phase:

- `src/oxion/collection/idempotency.gleam`
- `src/oxion/collection/dispatcher.gleam`
- `src/oxion/collection/scheduler.gleam`
- `conformance-checklist/phase-c-conformance-checklist.md`

---

## Phase D — RADIUS Path (Default `radius_only`)

### D1. Module: `oxCore.collection_orchestrator`

- **Submodule:** mapping action policy -> command orchestration
  - `apply_bandwidth_profile` -> `ChangePackage`
  - `suspend_service` -> `SuspendService`

### D2. Module: `oxRADIUS.coa_execution`

- **Submodule:** profile resolver (`profile_id` -> effective attr)
- **Submodule:** `send_coa_if_needed` guard
- **Submodule:** active profile snapshot/cache compare

### D3. Module: `oxCore.olt_guard`

- **Submodule:** enforcement target resolver
- **Submodule:** default safeguard `radius_only`

Entry criteria:

- Phase C complete.

Exit criteria:

- Throughput berubah sesuai policy via RADIUS path.
- OLT tidak tersentuh pada overdue default flow.
- CoA duplicate ter-skip dan tercatat.

Companion breakdown:

- `implementation/phase-d-production-breakdown.md`
- `conformance-checklist/phase-d-conformance-checklist.md`

Artefak phase:

- `src/oxion/orchestration/collection/commands.gleam`
- `src/oxion/orchestration/collection/orchestrator.gleam`
- `src/oxion/orchestration/collection/outcome.gleam`
- `src/oxion/orchestration/collection/audit.gleam`
- `src/oxion/orchestration/collection/olt_guard.gleam`
- `src/oxion/radius/packet.gleam`
- `src/oxion/radius/profile/types.gleam`
- `src/oxion/radius/profile/resolver.gleam`
- `src/oxion/radius/profile/snapshot.gleam`
- `src/oxion/radius/profile/normalizer.gleam`
- `src/oxion/radius/profile/diff.gleam`
- `src/oxion/radius/vendor/types.gleam`
- `src/oxion/radius/vendor/cisco.gleam`
- `src/oxion/radius/vendor/juniper.gleam`
- `src/oxion/radius/vendor/vbng.gleam`
- `src/oxion/radius/coa/request.gleam`
- `src/oxion/radius/coa/response.gleam`
- `src/oxion/radius/coa/result.gleam`
- `src/oxion/radius/coa/retry.gleam`
- `src/oxion/radius/coa/execution.gleam`
- `src/oxion/radius/coa/transport.gleam`
- `src/oxion_radius_transport_ffi.erl`
- `conformance-checklist/phase-d-conformance-checklist.md`

---

## Phase E — Notification and Payment Recovery

### E1. Module: `notification_engine.collection_templates`

- **Submodule:** stage-based template mapping
- **Submodule:** channel resolver (WA/Email/SMS/Push)

### E2. Module: `oxBill.payment_link_resolver`

- **Submodule:** static payment link mode
- **Submodule:** signed link mode + TTL

### E3. Module: `oxCore.restore_flow`

- **Submodule:** invoice paid event normalization
- **Submodule:** restore original profile
- **Submodule:** unsuspend if previously suspended by collection

Entry criteria:

- Phase D complete.

Exit criteria:

- Notifikasi collection terkirim sesuai stage.
- Payment link valid sesuai mode policy.
- Paid event mengembalikan service ke `operational_state=normal`.

---

## Phase F — UI Builder Minimum Viable

### F1. Module: `web.collection_policy_builder`

- **Submodule:** policy CRUD
- **Submodule:** stage/condition/action editor
- **Submodule:** simulate panel
- **Submodule:** publish workflow

Entry criteria:

- Phase E complete.

Exit criteria:

- Operator non-dev dapat create/simulate/publish policy tanpa edit code.

---

## Phase G — UAT, Hardening, and Operational Readiness

### G1. Module: `oxNOC.collection_observability`

- **Submodule:** metrics dashboard
  - evaluated
  - executed
  - skipped_idempotent
  - failed
- **Submodule:** alert baseline

### G2. Module: `qa.collection_test_matrix`

- **Submodule:** overlap stage test
- **Submodule:** duplicate scheduler run test
- **Submodule:** duplicate webhook paid test
- **Submodule:** signed link expiry test

### G3. Module: `ops.runbook`

- **Submodule:** rollback policy version
- **Submodule:** emergency disable stage
- **Submodule:** incident checklist

Entry criteria:

- Phase F complete.

Exit criteria:

- Semua strict scope pass di environment production-like.

---

## Phase H — oxBill Operator Layer (Dalo-Inspired, Platform-Grade)

### H1. Module: `oxBill.billing_plan_registry`

- **Submodule:** plan CRUD facade (operator-facing)
- **Submodule:** event emit (`billing.plan.created|updated|archived`)

### H2. Module: `oxBill.rate_catalog`

- **Submodule:** versioned rate catalog
- **Submodule:** lifecycle `draft/simulated/published/archived`
- **Submodule:** effective date handling

### H3. Module: `oxBill.pos_counter`

- **Submodule:** manual payment recording
- **Submodule:** receipt numbering + cashier trace

### H4. Module: `oxBill.payment_type_policy`

- **Submodule:** tenant/reseller payment-method enablement
- **Submodule:** constraints policy per payment type

### H5. Module: `oxBill.billing_history_query`

- **Submodule:** filterable history query API
- **Submodule:** query audit event (`billing.history.query_executed`)

Entry criteria:

- Phase C complete.

Exit criteria:

- Operator workflows setara kebutuhan dalo-style tersedia tanpa melanggar boundary policy-driven.
- Semua mutasi operator layer tetap command/event based dan auditable.

Artefak phase:

- `billing_plan_registry` schema + API
- `billing_rate_catalog` schema + lifecycle
- `billing_pos_transactions` schema + API
- `payment_type_policies` schema + API
- `billing_history_index` schema + API

---

## 6. MVP Gate (Binary Pass/Fail)

MVP = **PASS** hanya jika semua kondisi ini terpenuhi:

- [ ] Policy valid schema + EBNF conformance.
- [ ] Policy contoh berjalan: `6..20 -> bw_4mbps`, `>=21 -> suspend`.
- [ ] Enforcement scheduler aktif per tenant timezone.
- [ ] Idempotency guard mencegah action/CoA duplikat.
- [ ] OLT untouched untuk overdue default.
- [ ] Stage notification + payment link terkirim.
- [ ] Invoice paid memulihkan layanan normal otomatis.
- [ ] Semua action tercatat di audit log.

Jika satu saja gagal, status tetap **BELUM MVP**.

---

## 7. Test Evidence per Phase (Wajib)

Setiap phase harus menghasilkan bukti test sebelum phase dinyatakan selesai.

| Phase | Bukti Test Minimum |
| --- | --- |
| A | contract validation pass (`schema + EBNF conformance`) |
| B | deterministic evaluator tests + golden snapshots pass |
| C | idempotency tests pass + enforcement log assertions |
| D | integration tests `oxBill -> oxCore -> oxRADIUS` pass |
| E | restore flow tests + notification/payment-link tests pass |
| F | UI simulate/publish integration tests pass |
| G | packet-level checklist + UAT sign-off pass |
| H | operator-layer tests (plan/rate/POS/payment-type/history) + audit event assertions pass |

Rule lintas phase:

- Jika ada perubahan Gleam, wajib `gleam test` dan `gleam format --check src test`.
- Jika menyentuh stack lain (TS/Python/Elixir), wajib test stack terkait.
- Tanpa test evidence, phase tetap status `in_progress`.

---

## 8. Paralel Aman (Tanpa Merusak Critical Path)

- Penyusunan template notifikasi dapat jalan paralel sejak Phase C.
- Persiapan UI visual dapat dimulai paralel sejak Phase D.
- Dashboard observability dapat disiapkan paralel sebelum Phase G final.

Semua paralel harus tidak mengubah contract freeze (Phase A).

---

## 9. Out of Scope MVP

- Marketplace plugin publik.
- Rule builder visual advanced (drag-and-drop kompleks).
- Multi-policy conflict resolver advanced lintas tenant.
- Progressive rollout/A-B policy experimentation.

---

## 10. Risiko Utama dan Mitigasi

- Risiko: stage overlap menghasilkan aksi tidak konsisten.
  - Mitigasi: `priority + stop_on_match + simulator + tie-breaker stage.id`.

- Risiko: duplicate action dari retry/scheduler overlap.
  - Mitigasi: fingerprint unik + unique constraint + idempotent executor.

- Risiko: payment link disalahgunakan.
  - Mitigasi: signed mode, TTL ketat, scope per invoice/tenant.

- Risiko: drift lintas bahasa evaluator (`TS/Python/Elixir`).
  - Mitigasi: conformance suite wajib berbasis `collection-policy-ebnf.md`.
