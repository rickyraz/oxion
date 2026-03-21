# Phase A Conformance Checklist

## Scope

Phase A = Contract and Determinism Baseline.

Referensi: `../policies/oxion-mvp-fasttrack-plan.md`.

---

## Checklist

- [x] Contract schema tersedia: `../policies/collection-policy.schema.json`
- [x] EBNF/semantic spec tersedia: `../policies/collection-policy-ebnf.md`
- [x] Contract matrix tersedia: `../policies/collection-policy-contract-matrix.md`
- [x] Lifecycle transition rules terdokumentasi dan tidak ambigu
- [x] Single active published policy per tenant terdokumentasi
- [x] Determinism rule (`priority`, `stage.id`, `stop_on_match`) terdokumentasi
- [x] Gleam lifecycle transition tests tersedia (`test/oxion/policy/lifecycle_test.gleam`)

---

## Test Evidence (Current)

Perubahan phase ini menambahkan:

- `src/oxion/policy/lifecycle.gleam`
- `test/oxion/policy/lifecycle_test.gleam`
- coverage aktivasi `published-only`, conflict, dan archived immutability

Command verifikasi wajib:

- `gleam test`
- `gleam format --check src test`

Status verifikasi pada patch ini:

- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam test`.
- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam format --check src test`.
- Hasil: `23 passed, no failures`.
