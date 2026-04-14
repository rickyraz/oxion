# oxion

Oxion is a policy-driven repository using an Open Core model (Apache-2.0) with a private Enterprise Edition (EE) boundary.

## Current Layout

- `apps/` -> public backend Gleam services (`oxradius`, `oxcore`, `oxolt`, `oxnoc`)
- documentation content -> ignored in this repository; maintained in a separate documentation workspace
- `frontend/platform/` -> community/basic operator console for Platform Mode
- `packages/policy/` -> extracted policy package (single source policy logic)
- `packages/interop/` -> shared cross-app interop contract modules
- `schema/` -> optional schema-first area (non-primary for TS type generation)
- `generated/` -> committed generated artifacts from Gleam interfaces
- `scripts/` -> schema/codegen scripts
- `packages/` -> shared package area
- `tools/` -> operational helper tools

## Monorepo Tooling

- `pnpm-workspace.yaml` for workspace package discovery
- `nx.json` + `project.json` for cross-workspace task pipelines
- root `package.json` for command orchestration

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

Notes:

- Root `build/test/lint/typecheck` runs through Nx targets across the workspace.
- `generate:contracts` pulls source from public Gleam APIs (`packages/policy` + `packages/interop`)
  via `gleam export package-interface`.
- `generate:zod` maps `generated/interfaces/*.interface.json` to `generated/contracts.zod.ts`.

## Docs Entry

Documentation is maintained outside this repository (separate docs workspace/repo).
Open Core legal and architecture boundary references should be updated in that docs workspace.

## License and Trademark

- Code in this repository is licensed under [Apache License 2.0](LICENSE).
- Attribution notices are listed in [NOTICE](NOTICE).
- Trademark usage is governed by [TRADEMARKS.md](TRADEMARKS.md).
