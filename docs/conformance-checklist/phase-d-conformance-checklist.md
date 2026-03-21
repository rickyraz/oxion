# Phase D Conformance Checklist

## Scope

Phase D = RADIUS Path (default `radius_only`).

Referensi: `../policies/oxion-mvp-fasttrack-plan.md`.

---

## Implemented Artifacts

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
- `src/oxion/radius/coa/replay.gleam`
- `src/oxion/radius/coa/execution.gleam`
- `src/oxion/radius/coa/transport.gleam`
- `src/oxion/radius/disconnect/request.gleam`
- `src/oxion/radius/disconnect/response.gleam`
- `src/oxion/radius/disconnect/result.gleam`
- `src/oxion/radius/disconnect/execution.gleam`
- `src/oxion/radius/disconnect/transport.gleam`
- `src/oxion_radius_transport_ffi.erl`
- `src/oxion_radius_mock_transport_ffi.erl`
- `test/oxion/orchestration/collection/orchestrator_test.gleam`
- `test/oxion/orchestration/collection/olt_guard_test.gleam`
- `test/oxion/radius/profile/resolver_test.gleam`
- `test/oxion/radius/profile/diff_test.gleam`
- `test/oxion/radius/coa/request_test.gleam`
- `test/oxion/radius/coa/execution_test.gleam`
- `test/oxion/radius/coa/transport_test.gleam`
- `test/oxion/radius/coa/replay_test.gleam`
- `test/oxion/radius/disconnect/request_test.gleam`
- `test/oxion/radius/disconnect/execution_test.gleam`

---

## Checklist

- [x] Action runtime -> command orchestration mapping tersedia.
- [x] `radius_only` guard tersedia dan fail-closed untuk target tidak dikenal.
- [x] Vendor-aware profile resolver tersedia (`Cisco`, `Juniper`, `vBNG`).
- [x] Active snapshot + session selector model tersedia.
- [x] Profile diff/idempotent skip compare tersedia.
- [x] CoA request builder tersedia.
- [x] Disconnect request builder tersedia.
- [x] ACK/NAK/timeout/transport result model tersedia.
- [x] Retry policy tersedia dan tervalidasi.
- [x] `send_coa_if_needed` pure-domain coordinator tersedia.
- [x] Live UDP CoA sender/receiver adapter tersedia.
- [x] Live UDP Disconnect sender/receiver adapter tersedia.
- [x] Response authenticator verification tersedia.
- [x] Managed replay/runtime enforcement tersedia untuk `CoA` dan `Disconnect`.
- [x] Audit projection dari command outcome tersedia.

---

## Test Evidence

Command:

- `gleam test`
- `gleam format --check src test`

Perubahan test phase ini mencakup:

- mapping executed collection action -> radius command + side effect
- restore guard untuk `original_profile_id`
- target-state conflict detection di orchestration layer
- `radius_only` OLT guard block + unknown target fail-closed
- vendor profile resolution untuk Cisco mapping
- profile diff normalization terhadap urutan field dan duplicate attr
- request builder untuk suspend path + selector validation
- CoA execution path untuk idempotent skip, timeout->retry->ACK, NAK non-retryable, dan missing snapshot
- replay cache pure-domain untuk duplicate packet rejection
- live UDP roundtrip test untuk ACK, NAK, dan bad-auth response
- `send_coa_live` integration test via mock UDP server
- Disconnect builder dan managed live disconnect ACK path via mock UDP server
- duplicate Disconnect runtime execution ditolak oleh replay cache pada managed path

Status verifikasi pada patch ini:

- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam test`.
- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam format --check src test`.
- Hasil: `41 passed, no failures`.
