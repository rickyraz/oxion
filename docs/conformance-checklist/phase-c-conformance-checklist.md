# Phase C Conformance Checklist

## Scope

Phase C = Enforcement Runtime and Idempotency.

Referensi: `docs/oxion-mvp-fasttrack-plan.md`.

---

## Implemented Artifacts

- `src/oxion/collection/idempotency.gleam`
- `src/oxion/collection/dispatcher.gleam`
- `src/oxion/collection/scheduler.gleam`
- `test/oxion/collection/phase_c_test.gleam`

---

## Checklist

- [x] `action_fingerprint` generator tersedia.
- [x] Dedupe guard (`should_execute`) tersedia.
- [x] Dispatcher action policy -> dispatched action tersedia.
- [x] Scheduler runtime untuk candidate overdue tersedia.
- [x] Rerun scheduler tidak memicu duplicate action.
- [x] Executed vs skipped tracking tersedia.
- [x] Retry-safe executor tersedia (`execute_with_retry_from_attempts`).
- [x] Retry path test (success/fail/invalid config) tersedia.

---

## Test Evidence

Command:

- `gleam test`
- `gleam format --check src test`

Perubahan test phase ini mencakup:

- fingerprint uniqueness untuk action type yang sama dengan payload berbeda
- rerun dispatcher/scheduler tetap skip action instance yang sama
- scheduler audit detail (`executed_actions`, `skipped_actions`, `evaluation_error`)
- exposure config schedule (`timezone`, `evaluation_time`) untuk orchestration layer
- retry path tetap diuji (success/fail/invalid config)

Status verifikasi pada patch ini:

- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam test`.
- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam format --check src test`.
- Hasil: `23 passed, no failures`.
