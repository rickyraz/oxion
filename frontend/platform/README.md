# frontend/platform

TanStack Start app placeholder untuk Platform Mode (community/basic operator console).

Status saat ini: scaffold aktif dengan dependency Solid 2 beta + TanStack Start/Router beta alignment.

Boundary:

- public repo: community/basic operator UI
- private EE: advanced billing/orchestration enterprise UI

Next:

1. Lanjut migrasi dari router-only scaffold ke full TanStack Start runtime (SSR/server functions).
2. Hubungkan kontrak generated types dari `/generated`.
3. Tambahkan test cases nyata untuk route/rendering dan server-boundary.

## TanStack Solid v2 Alignment

Merujuk ke artikel TanStack "Solid 2.0 Beta Support in TanStack Router, Start, and Query" (Apr 10, 2026), package `frontend/platform` telah di-align ke jalur beta:

- `@tanstack/solid-router@2.0.0-beta.11`
- `@tanstack/solid-start@2.0.0-beta.12`
- `@tanstack/solid-router-devtools@2.0.0-beta.8`
- `solid-js@2.0.0-beta.5`
- `@solidjs/web@2.0.0-beta.5`
- `vite-plugin-solid@3.0.0-next.4`

Catatan: pada kombinasi beta saat ini, `@tanstack/solid-router-devtools` masih berpotensi bentrok saat production build. Komponen devtools sementara tidak dipasang di root route agar pipeline build tetap stabil.
