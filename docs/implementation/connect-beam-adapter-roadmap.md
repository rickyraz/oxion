# Connect BEAM Adapter Roadmap

## Tujuan

`connect-beam` adalah rencana adapter BEAM untuk pola Connect RPC di Oxion. Ini bukan pengganti HTTP boundary saat ini, melainkan jalur masa depan untuk API internal/operator yang butuh contract typed, error model konsisten, dan integrasi natural dengan TanStack frontend.

Pendekatan sekarang tetap berlaku:

- REST tetap dipakai untuk public/simple endpoints, health, metrics, webhooks, file download/upload, dan kompatibilitas integrasi eksternal.
- Gleam tetap source of truth untuk domain contract dan codegen awal.
- Frontend TanStack Start tetap memanggil backend melalui HTTP boundary yang jelas.
- `connect-beam` akan masuk sebagai adapter tipis di atas domain BEAM/Gleam, bukan tempat business rule.

## Target Arsitektur

```text
TanStack Start + SolidJS
  -> connect-query
  -> connect-es
  -> connect-beam adapter
  -> Gleam domain function / BEAM service facade
```

REST tetap hidup berdampingan:

```text
TanStack Start
  -> REST fetch
  -> public/simple endpoints
```

## Boundary Rule

- `api_gateway` tetap hanya routing, auth middleware, tenant resolution, rate limit, dan tracing.
- Connect adapter hanya decode request, auth/tenant/tracing context, dispatch ke domain function, lalu encode response.
- Business rule tetap berada di engine/domain module, bukan di adapter.
- Contract harus punya error model seragam: unauthenticated, permission denied, invalid argument, not found, failed precondition, internal.

## Kandidat Connect RPC

Domain yang paling layak dipindahkan bertahap ke Connect:

- Subscriber operator API: get/list/update, reset quota, disconnect, session/accounting view.
- Service inventory: get service, get state, activate, suspend, terminate, reconcile, change package.
- NAS/ONU operator API: get signal, test connection, configure ONU, schedule firmware upgrade.
- Billing operator API: invoice query, collection policy simulation/publish, payment state.
- Reports: overview, traffic, top users, NAS utilization, workflow summary.

REST tetap lebih cocok untuk:

- `/health`, `/health/ready`, `/metrics`
- FreeRADIUS internal hooks yang sudah stabil di `/v1/policy/*`
- payment/webhook callbacks
- public self-service endpoints yang sederhana
- file/PDF export/download endpoints

## Implementasi Bertahap

1. Pertahankan REST sebagai baseline.
2. Definisikan service contract untuk 1 bounded context kecil, misalnya `SubscriberService`.
3. Tambahkan `connect-beam` adapter sebagai facade BEAM tipis.
4. Generate client TypeScript untuk `connect-es`.
5. Gunakan `connect-query` di TanStack Start untuk query/mutation operator UI.
6. Setelah pola stabil, pindahkan domain kompleks: subscribers, services, NAS, billing, reports.

## Non-Goals Saat Ini

- Tidak mengganti seluruh REST API secara big-bang.
- Tidak memindahkan domain logic ke frontend.
- Tidak membuat adapter menyimpan business logic.
- Tidak menghapus GraphQL/WebSocket untuk realtime use case yang sudah cocok.
