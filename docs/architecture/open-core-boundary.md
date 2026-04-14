# Open-Core Boundary

Dokumen ini menetapkan boundary resmi antara komponen publik (Open Core) dan komponen private (Enterprise Edition) pada platform Oxion.

## Licensing Model

- Open Core: Apache License 2.0
- Enterprise Edition: proprietary (private repository)
- Trademark: lihat `TRADEMARKS.md`

## Public Scope (Apache-2.0)

- `apps/oxcore`
- `apps/oxradius`
- `apps/oxolt`
- `apps/oxnoc`
- `packages/policy`
- `packages/interop`
- `frontend/platform` (community/basic operator console)
- `scripts/`, `tools/`, `schema/`, `generated/` yang dibutuhkan untuk kontrak publik
- Dokumen publik di `docs/` kecuali detail implementasi internal EE

## Private Scope (EE)

- `apps/oxbill` runtime implementation
- advanced billing and collection intelligence
- advanced orchestration/reconciliation monetization logic
- enterprise-only connectors and commercial integrations
- premium dashboards and enterprise reporting controls

## Boundary Rules

- Public repo tidak boleh mengimpor runtime private secara langsung.
- Integrasi public-private wajib lewat kontrak/interoperability (`packages/interop`) atau adapter boundary.
- Public repo harus tetap `build`, `test`, dan `lint` hijau tanpa akses repo private.
- Dokumen publik hanya memuat contract-level behavior; detail strategi monetisasi internal disimpan di EE docs.
