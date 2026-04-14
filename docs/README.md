# Oxion Docs Map

Struktur `docs/` dipisah per fungsi dokumen agar boundary, kontrak, dan evidence lebih mudah diaudit.

## Repo Reality Check

Struktur repository saat ini:

- backend Gleam publik di `apps/` (`oxcore`, `oxradius`, `oxnoc`, `oxolt`)
- frontend publik di `frontend/platform` (community/basic console)
- policy contract di `packages/policy`
- shared interop contract di `packages/interop`

Boundary Open Core vs Enterprise Edition (EE) resmi:

- [Open-Core Boundary](architecture/open-core-boundary.md)

Untuk verifikasi Gleam lintas package:

```bash
node scripts/run-gleam-all.mjs format-check
node scripts/run-gleam-all.mjs check
node scripts/run-gleam-all.mjs test
```

## Folder Structure

```text
docs/
|-- architecture/           # overview platform, infra, services, naming, open-core boundary
|-- modules/                # bounded context specs (public), termasuk oxBill public summary
|-- policies/               # policy contract, schema, grammar, MVP plan
|-- implementation/         # engineering breakdown, roadmap, risk review
|-- interoperability/       # profile broadband dan packet-level references
|-- plugins/                # plugin architecture, examples, schema
|-- operations/             # migration runbook, testing strategy
|-- conformance-checklist/  # evidence per phase
`-- README.md
```

## Where To Start

1. [Platform Overview](architecture/oxion-platform-overview.md)
2. [Platform Purpose and System Thesis](architecture/oxion-platform-purpose-thesis.md)
3. [Infrastructure, Deployment, and Roadmap](architecture/oxion-infra-deployment-spec.md)
4. [Platform Services Specification](architecture/oxion-platform-services-spec.md)
5. [Open-Core Boundary](architecture/open-core-boundary.md)
6. [oxRADIUS Spec](modules/oxradius-spec.md)
7. [oxCore Spec](modules/oxcore-spec.md)
8. [oxOLT Spec](modules/oxolt-spec.md)
9. [oxBill Public Spec](modules/oxbill-spec.md)
10. [oxNOC Spec](modules/oxnoc-spec.md)
