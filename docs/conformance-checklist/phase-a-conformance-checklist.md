# Phase A Conformance Checklist

## Scope

Phase A = Contract and Determinism Baseline.

Referensi: `docs/oxion-mvp-fasttrack-plan.md`.

---

## Checklist

- [x] Contract schema tersedia: `docs/collection-policy.schema.json`
- [x] EBNF/semantic spec tersedia: `docs/collection-policy-ebnf.md`
- [x] Contract matrix tersedia: `docs/collection-policy-contract-matrix.md`
- [x] Lifecycle transition rules terdokumentasi dan tidak ambigu
- [x] Single active published policy per tenant terdokumentasi
- [x] Determinism rule (`priority`, `stage.id`, `stop_on_match`) terdokumentasi
- [x] Gleam lifecycle transition tests tersedia (`test/policy_lifecycle_test.gleam`)

---

## Test Evidence (Current)

Perubahan phase ini menambahkan:

- `src/policy_lifecycle.gleam`
- `test/policy_lifecycle_test.gleam`
- coverage aktivasi `published-only`, conflict, dan archived immutability

Command verifikasi wajib:

- `gleam test`
- `gleam format --check src test`

Status verifikasi pada patch ini:

- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam test`.
- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam format --check src test`.
- Hasil: `23 passed, no failures`.
