# AGENTS.md

## Agent Persona

You are a deterministic, policy-first engineering assistant.
Prioritaskan kejelasan boundary, test evidence, dan perubahan yang bisa diaudit.

## Project Context

Repo ini mengikuti pendekatan policy-driven, modular, dan deterministic.
Aturan utama ada di `CONTRIBUTING.md` dan wajib dipatuhi.

Struktur kerja yang paling penting:

- `apps/oxcore` -> orchestration + collection core.
- `apps/oxradius` -> RADIUS transport, CoA/PoD, profile, registry, UDP/RadSec.
- `apps/oxnoc` -> audit + DSR workflow.
- `apps/oxbill`, `apps/oxolt` -> package placeholder.
- `packages/policy` -> policy engine contract/type/evaluator/simulator/validator.
- `packages/interop` -> modul interop lintas app.
- `docs/` -> kontrak, flow, lifecycle, phase evidence, interop, operations.
- `docs/policies/` -> policy contract (`schema` + `EBNF`) dan MVP plan.
- `docs/conformance-checklist/` -> evidence per phase implementasi.

Read order minimum sebelum perubahan besar:

1. `CONTRIBUTING.md`
2. `AGENTS.md`
3. `docs/README.md`
4. `docs/policies/oxion-mvp-fasttrack-plan.md`
5. `docs/operations/oxion-testing-strategy.md`
6. `docs/policies/collection-policy.schema.json` + `docs/policies/collection-policy-ebnf.md`

## Environment Setup

Minimum tools:

- Gleam 1.x
- Erlang/OTP yang kompatibel dengan versi Gleam project
- Git

Opsional (hanya jika stack tersebut disentuh):

- Node.js 20+ (TypeScript modules/adapters)
- Python 3.11+ (scripts/services)
- Elixir 1.16+ (jika ada module ExUnit)

Setup baseline (repo ini):

```bash
node scripts/run-gleam-all.mjs check
```

## Non-Negotiable Rules

- Jangan hardcode business rule collection (hari/speed/vendor attr) di core.
- Jaga boundary module: policy engine != execution adapter.
- Semua perubahan behavior wajib disertai test pada stack yang relevan.
- Jika menyentuh phase di MVP plan, update test evidence phase tersebut.
- Semua action enforcement harus idempotent dan deterministic.

## Testing Requirements (Wajib Sebelum Commit)

Jika `Gleam` touched:

```bash
node scripts/run-gleam-all.mjs format-check
node scripts/run-gleam-all.mjs test
```

Jika `TypeScript` touched:

```bash
# jalankan test yang relevan untuk file/module yang diubah
npm test -- <path-to-related-test>
```

Jika `Python` touched:

```bash
# jalankan test yang relevan untuk file/module yang diubah
python -m pytest <path-to-related-test>
```

Jika `Elixir` touched:

```bash
# jalankan ExUnit yang relevan
mix test <path-to-related-test>
```

Jika `Policy contract` touched:

- update contract test + conformance test terhadap schema/EBNF.
- pastikan perubahan tetap selaras dengan `docs/policies/collection-policy.schema.json`.

Jika environment belum mendukung test tertentu, agent wajib:

- jelaskan test yang seharusnya dijalankan,
- jelaskan apa yang sudah diverifikasi secara manual,
- tulis follow-up verification step yang jelas dan dapat dieksekusi.

## Docs Sync Rules

Jika mengubah kontrak, flow, lifecycle, atau boundary:

- update dokumen terkait di `docs/`.
- pastikan `docs/README.md` tetap sinkron.
- sinkronkan minimal ke dokumen yang relevan:
  - `docs/architecture/` untuk perubahan arsitektur/deployment/API.
  - `docs/modules/` untuk perubahan bounded context module.
  - `docs/policies/` untuk perubahan contract/schema/grammar.
  - `docs/conformance-checklist/` untuk evidence phase.

## Boundaries (Do & Don't)

Do:

- pertahankan pemisahan intent/policy vs execution/mechanism.
- tambah/ubah test bersamaan dengan perubahan behavior.
- update docs saat kontrak/flow/lifecycle berubah.

Don't:

- jangan hardcode rule bisnis tenant-specific di core.
- jangan memindahkan vendor-specific logic ke policy core.
- jangan ubah struktur folder/module tanpa alasan bounded-context yang jelas.
- jangan skip test evidence untuk phase yang disentuh.

## Commit Discipline

Setelah format + test relevan lulus, usahakan langsung membuat commit atomik.

Rules:

- commit dilakukan **setelah** verification relevan selesai.
- satu commit hanya untuk satu concern engineering yang koheren.
- subject line wajib imperative present tense.
- subject line harus deskriptif, ringkas, dan terbaca tanpa konteks chat.
- body commit menjelaskan `what` dan `why` untuk perubahan non-trivial.
- hindari subject generik seperti `update`, `fix stuff`, `changes`, `wip`.
- jangan gabungkan refactor docs, hardening runtime, dan scaffold tak terkait dalam satu commit.

Target commit style:

- international engineering standard,
- silicon-valley grade readability,
- mudah dipindai di `git log --oneline` dan tetap jelas saat dibuka full message.
