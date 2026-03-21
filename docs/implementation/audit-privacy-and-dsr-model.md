# Audit Privacy and DSR Model

## 1. Tujuan

Dokumen ini mendefinisikan model target untuk dua hal yang sebelumnya masih kontradiktif di repo ini:

1. `audit_log` harus tetap append-only untuk kebutuhan akuntabilitas dan forensik,
2. platform tetap harus punya jalur yang masuk akal untuk `data subject request` (DSR), termasuk erasure, restriction, access, dan portability.

Dokumen ini adalah companion untuk:

- `docs/architecture/oxion-platform-services-spec.md`
- `docs/architecture/oxion-infra-deployment-spec.md`
- `docs/implementation/architecture-risk-review.md`
- `docs/implementation/oxradius-end-to-end-flow.md`

Dokumen ini menjelaskan model engineering dan operasional. Ini bukan legal advice final.

---

## 2. Prinsip Dasar

Model ini dibangun dengan prinsip berikut:

1. `audit_log` jangka panjang tidak boleh menjadi tempat pembuangan PII mentah.
2. Append-only hanya berlaku untuk event audit utama, bukan untuk setiap konteks sensitif pendukung.
3. DSR tidak boleh dimodelkan sebagai aksi sinkron tunggal seperti `DELETE /gdpr/erase`; harus ada workflow dengan verifikasi identitas, legal-hold check, dan eksekusi per data store.
4. Erasure bukan hak absolut. Bila ada kewajiban hukum atau kebutuhan legal claim, data tertentu dapat dipertahankan dengan pemrosesan yang dibatasi dan identitas yang diminimalkan.
5. Restriction berbeda dari erasure. Restriction berarti data pada dasarnya hanya disimpan dengan penggunaan yang sangat terbatas.
6. Backup immutable tidak diubah in-place; tetapi hasil DSR harus diterapkan ke live systems segera, dan backup harus dibiarkan age-out sesuai retention yang terdokumentasi.

---

## 3. Klasifikasi Data

### 3.1 Privacy Class

| Privacy Class | Contoh | Treatment Default |
| --- | --- | --- |
| `NoPersonalData` | event sistem, metric key, code path | boleh masuk audit utama |
| `PseudonymisedOperationalData` | `subject_alias`, service/package id, tenant-scoped opaque ref | boleh masuk audit utama |
| `DirectPersonalData` | nama, email, nomor telepon, username, alamat | jangan masuk audit utama jangka panjang |
| `SensitiveOperationalContext` | IP address lengkap, user agent lengkap, payload support yang mengandung PII | simpan terpisah, terenkripsi, short-retention |

### 3.2 Retention Class

| Retention Class | Tujuan | Contoh |
| --- | --- | --- |
| `ShortOperational` | troubleshooting dan support | raw request context, session trace detail |
| `SecurityForensic` | incident response dan abuse investigation | fingerprint, auth failure context |
| `ConsentEvidence` | bukti consent dan revocation | policy version, consent timestamp |
| `FinancialStatutory` | invoice, payment, tax, accounting | billing ledger, legal invoice references |
| `LongAudit` | accountability, change history, workflow evidence | audit event redacted |

### 3.3 Legal Basis

Field yang bersifat personal harus diberi legal basis yang jelas, minimal salah satu dari:

- `Contract`
- `LegalObligation`
- `LegitimateInterest`
- `Consent`
- `VitalInterest`
- `PublicTask`

Dalam praktik repo ini, yang paling sering relevan adalah `Contract`, `LegalObligation`, `LegitimateInterest`, dan `Consent`.

---

## 4. Model Audit yang Direkomendasikan

### 4.1 Audit Log Utama

`audit_log` tetap append-only, tetapi hanya menyimpan payload yang sudah direduksi dan dipseudonymise.

Field penting:

- `tenant_id`
- `actor_id`
- `actor_role`
- `action`
- `resource_type`
- `resource_ref`
- `subject_ref` bila memang perlu korelasi domain internal
- `subject_alias` sebagai alias stabil per tenant
- `change_summary` yang sudah di-redact
- `privacy_class`
- `retention_class`
- `legal_basis`
- `success`
- `error_code`
- `created_at`

Yang tidak boleh lagi menjadi field utama audit jangka panjang:

- `old_value` mentah
- `new_value` mentah
- `ip_address` lengkap
- `user_agent` lengkap

### 4.2 Private Context Side Store

Konteks sensitif yang masih diperlukan untuk troubleshooting atau security disimpan di side store terpisah, bukan di `audit_log` utama.

Contoh isinya:

- `ip_address`
- `user_agent`
- raw support payload yang mengandung PII
- request headers terbatas yang memang diperlukan untuk investigasi

Karakteristik side store:

- terenkripsi,
- short-retention,
- dapat dihapus atau di-crypto-shred saat retention habis atau saat DSR mengharuskannya,
- tidak menjadi sumber kebenaran jangka panjang.

Why: kalau `audit_log` long-retention dan append-only tetap menyimpan PII mentah, kamu hanya memindahkan masalah compliance ke tabel yang tidak boleh disentuh.

### 4.3 Stable Subject Alias

Gunakan `subject_alias` yang stabil per tenant untuk korelasi audit setelah direct identifier dihapus dari live domain store.

Sifat `subject_alias` yang disarankan:

- tidak memakai email/username mentah,
- dibangkitkan dari opaque internal subject reference,
- tenant-scoped,
- bisa dirotasi saat diperlukan,
- cukup stabil untuk forensik dan audit trend, tetapi tidak nyaman dipakai sebagai identitas publik.

---

## 5. Kontrak Event dan Schema Target

### 5.1 Target Event Contract

```gleam
pub type PrivacyClass {
  NoPersonalData
  PseudonymisedOperationalData
  DirectPersonalData
  SensitiveOperationalContext
}

pub type RetentionClass {
  ShortOperational
  SecurityForensic
  ConsentEvidence
  FinancialStatutory
  LongAudit
}

pub type LegalBasis {
  Contract
  LegalObligation
  LegitimateInterest
  Consent
  VitalInterest
  PublicTask
}

pub type AuditEvent {
  AuditEvent(
    id: String,
    tenant_id: String,
    actor_id: String,
    actor_role: String,
    action: AuditAction,
    resource_type: String,
    resource_ref: Option(String),
    subject_ref: Option(String),
    subject_alias: Option(String),
    change_summary: Json,
    privacy_class: PrivacyClass,
    retention_class: RetentionClass,
    legal_basis: LegalBasis,
    success: Bool,
    error_code: Option(String),
    timestamp: DateTime,
  )
}

pub type AuditPrivateContext {
  AuditPrivateContext(
    audit_id: String,
    purpose: String,
    encrypted_payload: Bytes,
    key_version: String,
    expires_at: DateTime,
  )
}
```

### 5.2 Target Schema

```sql
CREATE TABLE audit_log (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID NOT NULL,
  actor_id         UUID,
  actor_role       TEXT NOT NULL,
  action           TEXT NOT NULL,
  resource_type    TEXT NOT NULL,
  resource_ref     TEXT,
  subject_ref      UUID,
  subject_alias    TEXT,
  change_summary   JSONB NOT NULL DEFAULT '{}'::jsonb,
  privacy_class    TEXT NOT NULL,
  retention_class  TEXT NOT NULL,
  legal_basis      TEXT NOT NULL,
  success          BOOLEAN NOT NULL,
  error_code       TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON audit_log(tenant_id, created_at DESC);
CREATE INDEX ON audit_log(subject_alias, created_at DESC);
CREATE INDEX ON audit_log(resource_type, resource_ref);

CREATE TABLE audit_private_context (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id          UUID UNIQUE NOT NULL REFERENCES audit_log(id),
  purpose           TEXT NOT NULL,
  encrypted_payload BYTEA NOT NULL,
  key_version       TEXT NOT NULL,
  expires_at        TIMESTAMPTZ NOT NULL,
  erased_at         TIMESTAMPTZ
);
CREATE INDEX ON audit_private_context(expires_at);
```

Catatan penting:

- `audit_log` tetap immutable dan append-only.
- `audit_private_context` bukan append-only contract; row ini boleh dihapus atau di-crypto-shred sesuai retention atau hasil DSR.
- `change_summary` hanya berisi delta yang sudah dibersihkan dari PII mentah.

---

## 6. DSR Workflow

### 6.1 Request Types

DSR minimal yang harus dimodelkan:

- `Access`
- `Erasure`
- `Restriction`
- `Rectification`
- `Objection`
- `Portability`

### 6.2 Request Lifecycle

```text
submitted
  -> identity_verification_pending
  -> verified
  -> inventory_resolved
  -> execution_planned
  -> in_progress
  -> completed

failure branches:
  -> rejected
  -> blocked_by_legal_hold
  -> partially_completed
  -> cancelled
```

### 6.3 Execution Steps

Untuk setiap DSR, engine harus melakukan langkah berikut:

1. resolve subject dan tenant yang benar,
2. verifikasi identitas requester atau otoritas operator,
3. cek legal hold, retention, dan kewajiban hukum,
4. inventarisasi store yang terlibat,
5. tentukan action per store,
6. eksekusi action,
7. verifikasi hasil,
8. kirim report ke requester/operator,
9. emit audit event yang tetap redacted.

### 6.4 Store-Level Decision Matrix

| Store | Access | Erasure | Restriction | Portability |
| --- | --- | --- | --- | --- |
| subscriber profile | export | delete atau pseudonymise | freeze processing | include |
| active sessions/cache | export bila relevan | delete | stop non-essential processing | optional |
| accounting/invoice | export | retain bila ada legal obligation, direct identifier dipseudonymise | restrict non-required processing | include jika diwajibkan/tersedia |
| audit_log | export redacted events | tidak dihapus; tetap redacted dan minimised | tetap tersimpan, pemakaian dibatasi sesuai policy | include redacted subset |
| audit_private_context | biasanya tidak ikut export default | hapus atau crypto-shred | usage dibatasi | tidak default |
| consent records | export | retain minimal evidence sesuai legal basis | restrict future consent-driven use | include |
| backups | tidak menjadi jalur live export | biarkan age-out sesuai retention | jangan dipulihkan ke live untuk tujuan biasa | tidak default |

Why: erasure harus diputuskan per store, bukan dengan satu `DELETE` yang pura-pura menyelesaikan semua jenis data sekaligus.

---

## 7. API dan Workflow Contract

### 7.1 Endpoint yang Disarankan

Endpoint DSR sebaiknya dimodelkan sebagai workflow request, bukan aksi destruktif instan.

```text
POST   /v1/data-subject-requests
GET    /v1/data-subject-requests/:id
POST   /v1/data-subject-requests/:id/verify
POST   /v1/data-subject-requests/:id/cancel
GET    /v1/subscribers/:id/gdpr/export
POST   /v1/subscribers/:id/gdpr/erasure-requests
GET    /v1/subscribers/:id/consent
POST   /v1/subscribers/:id/consent
DELETE /v1/subscribers/:id/consent/:type
```

Catatan:

- `GET /v1/subscribers/:id/gdpr/export` masih bisa dipakai sebagai shortcut admin path bila policy mengizinkan.
- `DELETE /v1/subscribers/:id/gdpr/erase` sebaiknya dipensiunkan. Untuk platform-grade behavior, gunakan `POST /v1/subscribers/:id/gdpr/erasure-requests` atau `POST /v1/data-subject-requests`.

### 7.2 DSR Ledger

```sql
CREATE TABLE data_subject_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID NOT NULL,
  subject_ref         UUID NOT NULL,
  request_type        TEXT NOT NULL,
  status              TEXT NOT NULL,
  requested_by_actor  UUID,
  legal_hold          BOOLEAN NOT NULL DEFAULT FALSE,
  reason              TEXT,
  submitted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at        TIMESTAMPTZ
);

CREATE TABLE data_subject_request_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dsr_id              UUID NOT NULL REFERENCES data_subject_requests(id),
  store_name          TEXT NOT NULL,
  action              TEXT NOT NULL,
  status              TEXT NOT NULL,
  resolution_note     TEXT,
  executed_at         TIMESTAMPTZ
);
CREATE INDEX ON data_subject_request_items(dsr_id, store_name);
```

---

## 8. Implikasi ke Modul Platform

### 8.1 oxRADIUS

- emit audit payload yang sudah redacted,
- jangan mengirim raw `ip_address` dan `user_agent` ke `audit_log` utama,
- jika perlu context sensitif, tulis ke `audit_private_context` via audit service.

### 8.2 oxBill

- invoice dan payment ledger biasanya punya legal retention yang lebih kuat,
- DSR path untuk billing cenderung menghasilkan `RetainedUnderLegalObligation` atau pseudonymisation, bukan delete total.

### 8.3 oxCore / Workflow

- DSR sendiri sebaiknya diorkestrasi sebagai workflow,
- setiap store adapter harus mengembalikan outcome yang eksplisit: `Deleted`, `Pseudonymised`, `Retained`, `Restricted`, `NotFound`, atau `Rejected`.

### 8.4 oxNOC / Audit UI

- UI audit harus menampilkan redacted `change_summary`,
- akses ke private context harus dibatasi dan di-audit lagi,
- data yang sudah dihapus dari private context tidak boleh diam-diam fallback ke raw application logs.

---

## 9. Apa yang Benar Secara GDPR, dan Apa yang Belum

### 9.1 Yang Konsisten dengan Sumber Resmi

Model ini sengaja mengikuti batas yang konsisten dengan sumber resmi EU:

- right to erasure bukan hak absolut,
- data tidak boleh disimpan lebih lama dari yang diperlukan untuk tujuan yang sah,
- restriction berarti penyimpanan masih boleh terjadi dalam kasus tertentu, tetapi penggunaan harus dibatasi,
- controller harus dapat menjelaskan dasar hukum dan retention untuk tiap kategori data yang dipertahankan.

### 9.2 Yang Masih Bukan Garansi Compliance Otomatis

Walaupun model ini jauh lebih benar daripada spec lama, ini tetap belum otomatis membuat sistem menjadi fully compliant.

Masih perlu:

- record of processing activities,
- data inventory per processor/downstream,
- template response untuk DSR,
- retention schedule yang disahkan secara operasional,
- key management dan crypto-shredding procedure yang nyata,
- policy restore untuk backup pasca-erasure,
- review legal per yurisdiksi dan per produk mode.

---

## 10. Rekomendasi Implementasi Berikutnya

1. pindahkan emit audit runtime ke kontrak `change_summary + privacy_class + retention_class + legal_basis`,
2. tambahkan audit service adapter untuk `audit_private_context`,
3. bangun `data_subject_requests` workflow di platform layer,
4. wire DSR outcome ke `oxRADIUS`, `oxBill`, `oxCore`, dan `oxNOC`,
5. tambahkan test/spec evidence untuk redaction, retention expiry, dan legal-hold branches.

---

## 11. Referensi Resmi

- [European Commission: Do we always have to delete personal data if a person asks?](https://commission.europa.eu/law/law-topic/data-protection/rules-business-and-organisations/dealing-citizens/do-we-always-have-delete-personal-data-if-person-asks_en)
- [European Commission: For how long can data be kept?](https://commission.europa.eu/law/law-topic/data-protection/rules-business-and-organisations/principles-gdpr/how-long-can-data-be-kept-and-it-necessary-update-it_en)
- [European Commission: Information for individuals](https://commission.europa.eu/law/law-topic/data-protection/information-individuals_en)
- [EDPB: Respect individuals' rights](https://www.edpb.europa.eu/sme-data-protection-guide/respect-individuals-rights_en)
