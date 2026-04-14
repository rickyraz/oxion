# generated

Output-only folder untuk artefak hasil code generation dari source of truth Gleam.

Status keputusan saat ini:

- Folder ini **committed ke git** selama fase awal migrasi monorepo.
- TypeScript contracts dihasilkan dari:
  - `gleam export package-interface` untuk `packages/policy`
  - `gleam export package-interface` untuk `packages/interop`
- Artefak utama:
  - `contracts.generated.ts`
  - `contracts.zod.ts`
  - `interfaces/*.interface.json`
- Drift dicegah via command CI guard: `pnpm run check:generated`.

Alur generate:

1. `pnpm run generate:contracts`
2. `pnpm run generate:zod`
