# Phase D Conformance Checklist

## Scope

Phase D = RADIUS Path (default `radius_only`).

Referensi: `../policies/oxion-mvp-fasttrack-plan.md`.

---

## Implemented Artifacts

- `apps/oxcore/src/oxion/orchestration/collection/commands.gleam`
- `apps/oxcore/src/oxion/orchestration/collection/orchestrator.gleam`
- `apps/oxcore/src/oxion/orchestration/collection/outcome.gleam`
- `apps/oxcore/src/oxion/orchestration/collection/audit.gleam`
- `apps/oxcore/src/oxion/orchestration/collection/olt_guard.gleam`
- `apps/oxradius/src/oxion/radius/packet.gleam`
- `apps/oxradius/src/oxion/radius/profile/types.gleam`
- `apps/oxradius/src/oxion/radius/profile/resolver.gleam`
- `apps/oxradius/src/oxion/radius/profile/snapshot.gleam`
- `apps/oxradius/src/oxion/radius/profile/normalizer.gleam`
- `apps/oxradius/src/oxion/radius/profile/diff.gleam`
- `apps/oxradius/src/oxion/radius/udp/types.gleam`
- `apps/oxradius/src/oxion/radius/udp/worker.gleam`
- `apps/oxradius/src/oxion/radius/vendor/types.gleam`
- `apps/oxradius/src/oxion/radius/vendor/cisco.gleam`
- `apps/oxradius/src/oxion/radius/vendor/juniper.gleam`
- `apps/oxradius/src/oxion/radius/vendor/vbng.gleam`
- `apps/oxradius/src/oxion/radius/coa/request.gleam`
- `apps/oxradius/src/oxion/radius/coa/response.gleam`
- `packages/interop/src/oxion/radius/coa/result.gleam`
- `apps/oxradius/src/oxion/radius/coa/retry.gleam`
- `apps/oxradius/src/oxion/radius/coa/replay.gleam`
- `apps/oxradius/src/oxion/radius/coa/execution.gleam`
- `apps/oxradius/src/oxion/radius/coa/transport.gleam`
- `apps/oxradius/src/oxion/radius/dictionary/freeradius.gleam`
- `apps/oxradius/src/oxion/radius/disconnect/request.gleam`
- `apps/oxradius/src/oxion/radius/disconnect/response.gleam`
- `apps/oxradius/src/oxion/radius/disconnect/result.gleam`
- `apps/oxradius/src/oxion/radius/disconnect/execution.gleam`
- `apps/oxradius/src/oxion/radius/disconnect/transport.gleam`
- `apps/oxradius/src/oxion/radius/ops/status.gleam`
- `apps/oxradius/src/oxion/radius/ops/healthcheck.gleam`
- `apps/oxradius/src/oxion/radius/ops/radclient.gleam`
- `apps/oxradius/src/oxion/radius/radsec/types.gleam`
- `apps/oxradius/src/oxion/radius/radsec/certs.gleam`
- `apps/oxradius/src/oxion/radius/radsec/transport.gleam`
- `apps/oxradius/src/oxion_radius_transport_ffi.erl`
- `apps/oxradius/src/oxion_radius_mock_transport_ffi.erl`
- `apps/oxcore/test/oxion/orchestration/collection/orchestrator_test.gleam`
- `apps/oxcore/test/oxion/orchestration/collection/olt_guard_test.gleam`
- `apps/oxradius/test/oxion/radius/profile/resolver_test.gleam`
- `apps/oxradius/test/oxion/radius/profile/diff_test.gleam`
- `apps/oxradius/test/oxion/radius/coa/request_test.gleam`
- `apps/oxradius/test/oxion/radius/coa/execution_test.gleam`
- `apps/oxradius/test/oxion/radius/coa/transport_test.gleam`
- `apps/oxradius/test/oxion/radius/udp/worker_test.gleam`
- `apps/oxradius/test/oxion/radius/coa/replay_test.gleam`
- `apps/oxradius/test/oxion/radius/dictionary/freeradius_test.gleam`
- `apps/oxradius/test/oxion/radius/disconnect/request_test.gleam`
- `apps/oxradius/test/oxion/radius/disconnect/execution_test.gleam`
- `apps/oxradius/test/oxion/radius/ops/healthcheck_test.gleam`
- `apps/oxradius/test/oxion/radius/radsec/transport_test.gleam`

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
- [x] UDP worker reuse dan outstanding request tracking tersedia pada prepared live transport seam.
- [x] `Status-Server` ops path dan `radclient` rendering baseline tersedia.
- [x] Dictionary FreeRADIUS merender physical AVP/VSA yang terdeduplikasi dari logical registry.
- [x] `RadSec` transport planning baseline tersedia dari endpoint registry dan TLS config.
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
- reusable UDP worker menjaga outstanding request table, prune timeout, dan prepared roundtrip path untuk CoA/Disconnect
- `Status-Server` live smoke path, health classification, dan `radclient` command rendering baseline tersedia
- FreeRADIUS dictionary rendering memverifikasi bahwa banyak logical vendor attr dapat jatuh ke satu physical VSA yang sama secara benar
- `RadSec` config validation dan endpoint planning memiliki regression test untuk mTLS, verification mode, dan transport-kind mismatch

Status verifikasi pada patch ini:

- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam test`.
- Diverifikasi tanggal 2026-03-21 via `mise x gleam@1.15.2 -- gleam format --check src test`.
- Hasil: `41 passed, no failures`.
