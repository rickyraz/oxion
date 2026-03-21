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

1. **Gleam touched** -> jalankan `gleam test` dan `gleam format --check src test`.
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
