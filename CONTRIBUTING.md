# Contributing Guide

## Purpose

Dokumen ini menjadi aturan utama implementasi kode untuk repo Oxion.

Fokus utama:

- modular dan orthogonal design
- code style konsisten
- setiap phase implementasi wajib punya testing

---

## Read Order (Wajib)

1. `CONTRIBUTING.md`
2. `AGENTS.md`
3. `docs/README.md`
4. `docs/policies/oxion-mvp-fasttrack-plan.md`
5. `docs/operations/oxion-testing-strategy.md`
6. `docs/policies/collection-policy.schema.json` + `docs/policies/collection-policy-ebnf.md`

---

## Engineering Rules

- Satu module/satu tanggung jawab utama (do one thing well).
- Pisahkan policy dari mechanism.
- Hindari hardcoded business rule (hari, speed, vendor attr) di core.
- Semua perubahan behavior harus traceable (audit + metrics).
- Semua action enforcement wajib idempotent.

---

## Code Style and Structure

- Ikuti style native tiap bahasa (Gleam/TS/Python/Elixir) dan formatter resmi.
- Jangan tambahkan folder/module baru tanpa alasan bounded-context yang jelas.
- Simpan vendor-specific logic di adapter/profile layer, bukan core logic.

---

## Mandatory Testing Per Change

Setiap implementasi phase **wajib** menyertakan testing pada Gleam dan stack terkait yang disentuh.

### Minimal matrix

- Jika ubah `Gleam` domain/core:
  - wajib `node scripts/run-gleam-all.mjs test`
  - wajib `node scripts/run-gleam-all.mjs format-check`
- Jika ubah `TypeScript`:
  - wajib unit test TS terkait module
- Jika ubah `Python`:
  - wajib unit test Python terkait module
- Jika ubah `Elixir`:
  - wajib ExUnit test terkait module
- Jika ubah schema/contract policy:
  - wajib contract test + conformance test ke EBNF
- Jika ubah flow RADIUS/NAS/CoA:
  - wajib integration test + packet-level checklist update

### Phase gate rule

Untuk setiap phase di `docs/policies/oxion-mvp-fasttrack-plan.md`, PR harus menyertakan:

1. daftar test yang ditambahkan/diupdate,
2. hasil test pass,
3. jika ada test belum bisa dijalankan, tulis reason + follow-up task.

Tanpa test evidence, phase dianggap belum selesai.

---

## PR Checklist (Wajib Isi)

- [ ] Scope perubahan mengikuti boundary module/submodule.
- [ ] Tidak menambah hardcoded business rule di core.
- [ ] Test baru/updated sudah ditambahkan untuk area yang diubah.
- [ ] `node scripts/run-gleam-all.mjs test` pass.
- [ ] `node scripts/run-gleam-all.mjs format-check` pass.
- [ ] Docs terkait sudah diupdate (jika kontrak/flow berubah).

---

## Commit and Review

- Setelah verification yang relevan lulus, usahakan langsung commit secara atomik.
- Commit message harus deskriptif, memakai imperative present tense, dan jelas menjelaskan `what` + `why`.
- Subject line harus layak dibaca engineer internasional tanpa perlu konteks chat.
- Reviewer berhak reject jika test tidak memadai untuk phase yang diubah.
- Perubahan besar lintas stack wajib pecah jadi beberapa PR kecil agar mudah di-review.
