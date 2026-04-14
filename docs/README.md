# Oxion Docs Map

Struktur `docs/` sekarang dipisah berdasarkan fungsi dokumen, bukan dibiarkan datar.

## Repo Reality Check

Struktur repository saat ini sudah masuk mode monorepo:

- backend Gleam terpisah di `apps/` (`oxcore`, `oxradius`, `oxnoc`, `oxolt`, `oxbill`),
- frontend ada di `frontend/platform`,
- policy diextract ke `packages/policy`,
- shared interop contract ada di `packages/interop`.

Untuk command verifikasi Gleam lintas package, gunakan:

```bash
node scripts/run-gleam-all.mjs format-check
node scripts/run-gleam-all.mjs check
node scripts/run-gleam-all.mjs test
```

## Folder Structure

```text
docs/
├── architecture/           # overview platform, infra, services, naming
├── modules/                # spec bounded context utama: oxRADIUS, oxCore, oxOLT, oxBill, oxNOC
├── policies/               # contract, schema, grammar, MVP plan policy/billing
├── implementation/         # breakdown, roadmap, interop standard, risk review
├── interoperability/       # profile broadband, example packet, vendor template, checklist packet
├── plugins/                # plugin architecture, examples, schema, starter manifests
├── operations/             # migration runbook, testing strategy
├── conformance-checklist/  # evidence per phase
└── README.md
```

## Folder Guide

- `architecture/`
  - dokumen platform level yang menjelaskan arah produk, deployment, dan service boundary.
- `modules/`
  - spec untuk big modules utama yang jadi bounded context runtime.
- `policies/`
  - schema, EBNF, contract matrix, dan plan MVP policy/collection.
- `implementation/`
  - catatan engineering yang lebih operasional: breakdown phase, hardening roadmap, findings, risk review.
- `interoperability/`
  - dokumen jaringan dan RADIUS yang sifatnya vendor-facing atau packet-facing.
- `plugins/`
  - arsitektur plugin, example, schema, dan starter manifest.
- `operations/`
  - runbook migrasi dan strategi verifikasi/testing.
- `conformance-checklist/`
  - bukti implementasi per phase.

## Where To Start

Kalau mau memahami platform dari atas ke bawah, baca urut ini:

1. [Platform Overview](architecture/oxion-platform-overview.md)
2. [Platform Purpose and System Thesis](architecture/oxion-platform-purpose-thesis.md)
3. [Infrastructure, Deployment, and Roadmap](architecture/oxion-infra-deployment-spec.md)
4. [Platform Services Specification](architecture/oxion-platform-services-spec.md)
5. [oxRADIUS Spec](modules/oxradius-spec.md)
6. [oxCore Spec](modules/oxcore-spec.md)
7. [oxOLT Spec](modules/oxolt-spec.md)
8. [oxBill Spec](modules/oxbill-spec.md)
9. [oxNOC Spec](modules/oxnoc-spec.md)

Kalau fokusnya implementation hardening yang sedang aktif:

1. [MVP Fast-Track Plan](policies/oxion-mvp-fasttrack-plan.md)
2. [Phase D Production Breakdown](implementation/phase-d-production-breakdown.md)
3. [oxRADIUS End-to-End Flow](implementation/oxradius-end-to-end-flow.md)
4. [FreeRADIUS Interop Standard](implementation/freeradius-interop-standard.md)
5. [Radius Hardening Roadmap](implementation/radius-hardening-roadmap.md)
6. [Architecture Risk Review](implementation/architecture-risk-review.md)
7. [Audit Privacy and DSR Model](implementation/audit-privacy-and-dsr-model.md)
8. [Codex Next-Session Handoff](implementation/codex-next-session-handoff.md)
9. [Future Rustler NIF External Type Pattern](implementation/rustler-nif-external-type-pattern.md)
10. [Connect BEAM Adapter Roadmap](implementation/connect-beam-adapter-roadmap.md)

Kalau fokusnya contract dan conformance:

1. [Collection Policy Schema](policies/collection-policy.schema.json)
2. [Collection Policy EBNF](policies/collection-policy-ebnf.md)
3. [Collection Policy Contract Matrix](policies/collection-policy-contract-matrix.md)
4. [Phase A Checklist](conformance-checklist/phase-a-conformance-checklist.md)
5. [Phase B Checklist](conformance-checklist/phase-b-conformance-checklist.md)
6. [Phase C Checklist](conformance-checklist/phase-c-conformance-checklist.md)
7. [Phase D Checklist](conformance-checklist/phase-d-conformance-checklist.md)

## Reference Sets

- Plugin:
  - [Plugin Architecture](plugins/oxion-plugin-architecture.md)
  - [Plugin Examples](plugins/oxion-plugin-examples.md)
  - [Plugin Manifest Schema](plugins/plugin-manifest.schema.json)
  - [Plugin Starter README](plugins/plugin-starter/README.md)
- Interoperability:
  - [Tier-1 Broadband Interoperability Profile](interoperability/oxion-tier1-broadband-interoperability-profile.md)
  - [RADIUS Access-Accept and CoA Examples](interoperability/radius-access-coa-examples.md)
  - [NAS Vendor Mapping Template](interoperability/nas-vendor-mapping-template.md)
  - [Broadband Packet Validation Checklist](interoperability/broadband-packet-validation-checklist.md)
- Operations:
  - [daloRADIUS Migration Runbook](operations/oxion-dalo-migration-runbook.md)
  - [Testing Strategy](operations/oxion-testing-strategy.md)

## Product Modes

- **Lite Mode**
  - panel FreeRADIUS-style untuk skenario kecil, lab, atau single POP.
- **Platform Mode**
  - kapabilitas Oxion penuh untuk multi-tenant, orchestration, dan observability lengkap.

Jalur adopsi yang disarankan:

1. Mulai dari Lite Mode.
2. Migrasi data daloRADIUS dari MySQL/MariaDB via migration wizard.
3. Naik ke Platform Mode dan konsolidasi penuh di PostgreSQL 18.
