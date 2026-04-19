# oxion

Oxion is a policy-driven repository using an Open Core model (Apache-2.0) with a private Enterprise Edition (EE) boundary.

## What Is Oxion?

Oxion is an **ISP Operating Platform**.

In many ISP environments, AAA/RADIUS, OLT management, and billing are handled in separate tools, with manual handoffs between teams. Oxion acts as a unified control plane that coordinates those systems so service lifecycle operations become automated, auditable, and consistent.

Core idea:

- `oxCore` holds intent and service state (orchestrator + inventory)
- `oxRADIUS` executes AAA and policy decisions
- `oxOLT` executes fiber/OLT provisioning actions
- `oxNOC` provides operational visibility
- `oxBill (EE)` handles billing and payments

Practical outcome:

- fewer manual handoffs between billing, AAA, and network teams
- faster activation/suspension flows
- less state drift between business systems and network execution

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

## Versioning and Release

This repository uses Changesets for versioning and GitHub integration.

Local commands:

```sh
pnpm changeset            # create a changeset entry
pnpm version:packages     # apply version bumps + changelog updates
pnpm release              # publish releasable packages (when configured)
```

GitHub workflows:

- `.github/workflows/test.yml` runs CI checks (`lint`, `typecheck`, `test`)
- `.github/workflows/release.yml` runs Changesets automation to open/update a version PR on `main/master`, and publish when releasable packages exist
- `.github/workflows/github-release-on-tag.yml` creates a GitHub Release whenever a `v*` tag is pushed

Initial release example (`0.0.1`):

```sh
git tag -a v0.0.1 -m "initial release 0.0.1"
git push origin v0.0.1
```

## Docs Entry

Documentation is maintained outside this repository (separate docs workspace/repo).
Open Core legal and architecture boundary references should be updated in that docs workspace.

## EE Integration

- Private EE billing runtime repository: `https://github.com/rickyraz/oxion-ee-oxbill`
- Public contract changes must be synchronized with EE implementation notes.

## License and Trademark

- Code in this repository is licensed under [Apache License 2.0](LICENSE).
- Attribution notices are listed in [NOTICE](NOTICE).
- Trademark usage is governed by [TRADEMARKS.md](TRADEMARKS.md).
