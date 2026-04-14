# oxion

Oxion adalah repo policy-driven dengan model Open Core (Apache-2.0) dan boundary Enterprise Edition (EE) private.

## Current Layout

- `apps/` -> backend Gleam services publik (`oxradius`, `oxcore`, `oxolt`, `oxnoc`)
- `docs/` -> architecture, modules, policies, operations, conformance
- `frontend/platform/` -> community/basic operator console untuk Platform Mode
- `packages/policy/` -> extracted policy package (single source policy logic)
- `packages/interop/` -> shared interop contract modules lintas app
- `schema/` -> optional schema-first area (non-primary for TS type generation)
- `generated/` -> committed generated artifacts from Gleam interfaces
- `scripts/` -> schema/codegen scripts
- `packages/` -> shared package area
- `tools/` -> operational helper tools

## Monorepo Tooling

- `pnpm-workspace.yaml` untuk workspace package discovery
- `nx.json` + `project.json` untuk pipeline task lintas workspace
- `package.json` root untuk command orchestration

## Development Commands

Gleam:

```sh
node scripts/run-gleam-all.mjs format-check
node scripts/run-gleam-all.mjs check
node scripts/run-gleam-all.mjs test
node scripts/run-gleam-all.mjs build
```

Monorepo root (pnpm + Nx):

```sh
pnpm run dev
pnpm run build
pnpm run test
pnpm run lint
pnpm run typecheck
pnpm run generate
pnpm run check:generated
```

Catatan:

- Root `build/test/lint/typecheck` dijalankan oleh target Nx lintas workspace.
- `generate:contracts` mengambil source dari public API Gleam (`packages/policy` + `packages/interop`)
  via `gleam export package-interface`.
- `generate:zod` memetakan `generated/interfaces/*.interface.json` ke `generated/contracts.zod.ts`.

## Docs Entry

Mulai dari [docs/README.md](docs/README.md) untuk peta dokumen lengkap.
Boundary legal/arsitektur Open Core ada di [docs/architecture/open-core-boundary.md](docs/architecture/open-core-boundary.md).

## License and Trademark

- Code in this repository is licensed under [Apache License 2.0](LICENSE).
- Attribution notices are listed in [NOTICE](NOTICE).
- Trademark usage is governed by [TRADEMARKS.md](TRADEMARKS.md).
