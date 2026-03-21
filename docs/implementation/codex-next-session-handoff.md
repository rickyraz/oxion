# Codex Next-Session Handoff

## 1. Tujuan

Dokumen ini adalah handoff praktis untuk sesi Codex berikutnya agar bisa:

- melanjutkan implementasi tanpa membaca ulang seluruh repo dari nol,
- mengevaluasi kualitas perubahan yang baru masuk,
- membedakan mana yang sudah wired dan mana yang masih in-memory placeholder.

Tanggal konteks kerja: `2026-03-21`

---

## 2. Commit Penting Terbaru

Urutan commit yang relevan untuk area privacy, audit, dan DSR:

1. `ac99671` `Define a GDPR-compatible audit privacy model and DSR workflow`
2. `318d0cc` `Add a redacted runtime audit adapter for collection command outcomes`
3. `3a5422d` `Implement a runtime DSR workflow with store-level execution planning`
4. `HEAD` sesi ini:
   - audit persistence adapter,
   - DSR executor + bounded-context store adapters,
   - handoff doc ini.

Kalau sesi berikutnya ingin review dengan cepat, baca diff mulai dari `ac99671` ke `HEAD`.

---

## 3. Artefak Runtime Yang Sekarang Sudah Ada

### 3.1 Platform Audit

File utama:

- `src/oxion/platform/audit/types.gleam`
- `src/oxion/platform/audit/adapter.gleam`
- `src/oxion/platform/audit/persistence.gleam`
- `src/oxion/platform/audit/service.gleam`

Status sekarang:

- collection command outcome bisa diubah menjadi `AuditEnvelope` redacted,
- envelope bisa dipersist ke table-shaped store:
  - `audit_log`
  - `audit_private_context`
- duplicate event id dan duplicate private context id sudah dijaga.

Yang masih belum nyata:

- belum ada DB adapter sungguhan,
- belum ada migration/schema runtime,
- belum ada persistence adapter untuk query/reporting selain in-memory list store.

### 3.2 Platform DSR

File utama:

- `src/oxion/platform/dsr/types.gleam`
- `src/oxion/platform/dsr/workflow.gleam`
- `src/oxion/platform/dsr/executor.gleam`
- `src/oxion/platform/dsr/adapters/oxradius.gleam`
- `src/oxion/platform/dsr/adapters/oxbill.gleam`
- `src/oxion/platform/dsr/adapters/oxcore.gleam`
- `src/oxion/platform/dsr/adapters/oxnoc.gleam`

Status sekarang:

- DSR punya state machine dasar,
- inventory bisa di-resolve,
- action bisa direncanakan per store,
- executor bisa route ke adapter yang tepat,
- `oxRADIUS`, `oxBill`, `oxCore`, `oxNOC` sudah punya adapter state in-memory masing-masing.

Yang masih belum nyata:

- adapter masih state in-memory, belum DB/API/store sungguhan,
- belum ada authn/authz requester,
- belum ada export packaging,
- belum ada legal-hold source nyata,
- belum ada propagation ke processor eksternal.

---

## 4. Test Yang Sudah Menjaga Area Ini

### Audit

- `test/oxion/platform/audit/adapter_test.gleam`
- `test/oxion/platform/audit/persistence_test.gleam`

### DSR

- `test/oxion/platform/dsr/workflow_test.gleam`
- `test/oxion/platform/dsr/executor_test.gleam`

### Full repo baseline saat handoff ini dibuat

Jalankan:

```bash
mise x gleam@1.15.2 -- gleam format --check src test
mise x gleam@1.15.2 -- gleam test
```

Expected baseline: semua pass.

---

## 5. Hal Yang Paling Layak Dievaluasi Berikutnya

### 5.1 Audit Persistence

Evaluasi ini:

1. apakah `AuditStore` perlu dipisah jadi read/write adapter,
2. apakah duplicate guard cukup atau perlu unique key tambahan,
3. apakah `recorded_at` dan `expires_at` perlu type waktu yang lebih kuat,
4. apakah `private_context` perlu key metadata untuk crypto-shredding yang lebih nyata.

### 5.2 DSR Executor

Evaluasi ini:

1. apakah mapping store -> bounded context sudah tepat,
2. apakah `ConsentRecords` lebih cocok di `oxCore` atau bounded context lain,
3. apakah `Backups` sebaiknya diwakili sebagai adapter khusus infra, bukan `oxCore`,
4. apakah partial failure perlu model retry/compensation per adapter,
5. apakah `Rectification` dan `Objection` butuh action type yang lebih preskriptif daripada `ReviewStore`.

### 5.3 Runtime Integration

Prioritas implementasi berikutnya yang paling masuk akal:

1. ganti audit in-memory persistence dengan adapter DB sungguhan,
2. ganti DSR store adapters in-memory dengan adapter per module sungguhan,
3. tambahkan request identity proof / legal-hold source nyata,
4. sambungkan DSR workflow ke audit service sehingga tiap state transition juga ter-audit.

---

## 6. Review Checklist untuk Session Berikutnya

Kalau sesi berikutnya diminta review, cek cepat ini:

1. boundary tetap bersih: `workflow` tidak tahu detail persistence,
2. adapter tetap bounded-context specific, bukan switch monster,
3. audit main event tetap redacted,
4. private context tidak bocor ke audit utama,
5. DSR legal-hold branch tetap fail-closed,
6. test integration masih memaksa route ke semua adapter domain,
7. docs `oxradius-end-to-end-flow.md` dan `oxion-platform-services-spec.md` masih sinkron dengan runtime.

---

## 7. Dokumen Pendamping Yang Harus Dibaca Dulu

1. `docs/implementation/audit-privacy-and-dsr-model.md`
2. `docs/implementation/oxradius-end-to-end-flow.md`
3. `docs/architecture/oxion-platform-services-spec.md`
4. `docs/implementation/architecture-risk-review.md`
5. `docs/implementation/radius-hardening-roadmap.md`
