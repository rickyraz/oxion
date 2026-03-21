# AGENTS.md

## Agent Context

Repo ini memakai pendekatan policy-driven, modular, dan deterministic.
Agent harus mengikuti aturan di `CONTRIBUTING.md`.

## Non-Negotiable Rules

- Jangan hardcode business rule collection (hari/speed/vendor attr) di core.
- Jaga boundary module: policy engine != execution adapter.
- Semua perubahan behavior wajib disertai test pada stack yang relevan.
- Jika menyentuh phase di MVP plan, update test evidence phase tersebut.

## Testing Requirements for Agent Work

Saat agent mengubah kode:

1. **Gleam touched** -> jalankan `gleam format --check src test` dan `gleam test`.
2. **TypeScript touched** -> tambah/jalankan test TS terkait.
3. **Python touched** -> tambah/jalankan test Python terkait.
4. **Elixir touched** -> tambah/jalankan ExUnit terkait.
5. **Policy contract touched** -> update contract/conformance tests.

Jika environment belum mendukung menjalankan test tertentu, agent wajib:

- jelaskan test yang seharusnya dijalankan,
- jelaskan apa yang sudah diverifikasi,
- tulis follow-up verification step.

## Docs Sync Rules

Jika mengubah kontrak, flow, atau lifecycle:

- update docs terkait di `docs/`
- pastikan `docs/README.md` tetap sinkron

## Commit Discipline

Setelah perubahan selesai dan verifikasi relevan sudah lulus, agent harus mengusahakan langsung membuat commit yang atomik.

Rules:

- commit dilakukan **setelah** format dan test relevan selesai,
- satu commit hanya untuk satu concern engineering yang koheren,
- subject line pakai gaya imperative present tense,
- subject line harus deskriptif, ringkas, dan layak dibaca engineer global tanpa konteks chat,
- body commit harus menjelaskan `what` dan `why` saat perubahan tidak trivial,
- hindari subject generik seperti `update`, `fix stuff`, `changes`, `wip`,
- jangan menggabungkan refactor docs, hardening runtime, dan scaffold lain yang tidak satu concern ke commit yang sama.

Commit style target:

- international engineering standard,
- silicon-valley grade readability,
- mudah dipindai di `git log --oneline` dan tetap jelas saat dibuka full message.
