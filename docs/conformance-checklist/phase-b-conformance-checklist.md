# Phase B Conformance Checklist

## Scope

Phase B = Policy Engine Core.

Referensi: `docs/oxion-mvp-fasttrack-plan.md`.

---

## Implemented Artifacts

- `src/policy_types.gleam`
- `src/policy_validator.gleam`
- `src/policy_evaluator.gleam`
- `src/policy_simulator.gleam`
- `test/policy_phase_b_test.gleam`

---

## Checklist

- [x] Policy validator tersedia (structure + semantic checks).
- [x] Condition AST evaluator tersedia (`all/any/rule`).
- [x] Stage ordering deterministic (`priority` + tie-break `stage.id`).
- [x] `stop_on_match` behavior diimplementasikan.
- [x] Simulator policy range tersedia.
- [x] Deterministic output test tersedia.

---

## Test Evidence

Command:

- `gleam test`
- `gleam format --check src test`

Perubahan test phase ini mencakup:

- validator root contract (`name`, `description`, `timezone`, `grace_days`, `context`)
- validator action payload/plugin/channel constraints
- evaluator structured error contract (`code`, `stage_id`, `path`, `reason`)
- simulator output detail (`stage + actions + reason`) dan grace handling
- deterministic ordering tetap dipertahankan

Status verifikasi pada patch ini:

- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam test`.
- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam format --check src test`.
- Hasil: `23 passed, no failures`.
