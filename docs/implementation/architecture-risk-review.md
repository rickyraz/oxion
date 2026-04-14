# Architecture Risk Review

## 1. Tujuan

Dokumen ini mengubah 9 temuan arsitektur menjadi review yang bisa dipakai untuk:

- memisahkan risk yang benar-benar substantif dari risk yang salah framing,
- menandai gap spec yang perlu diperbaiki sebelum hardening berikutnya,
- menurunkan risk menjadi backlog implementasi prioritas.

Dokumen ini membaca repo pada kondisi saat ini. Review ini menilai:

- `docs/modules/oxcore-spec.md`
- `docs/modules/oxradius-spec.md`
- `docs/modules/oxolt-spec.md`
- `docs/modules/oxbill-spec.md`
- `docs/architecture/oxion-infra-deployment-spec.md`
- `docs/architecture/oxion-platform-services-spec.md`
- `docs/operations/oxion-dalo-migration-runbook.md`

Companion docs:

- `docs/implementation/phase-d-production-breakdown.md`
- `docs/implementation/freeradius-interop-standard.md`
- `docs/implementation/radius-hardening-roadmap.md`
- `docs/implementation/audit-privacy-and-dsr-model.md`

---

## 2. Ringkasan Eksekutif

Verdict ringkas untuk 9 poin:

- `Valid / substantif`: `1`, `2`, `3`, `5`, `6`, `9`
- `Valid tapi framing awalnya meleset`: `4`, `8`
- `False positive`: `7`

Implikasi utamanya:

1. Risk terbesar sekarang bukan sekadar codec packet, tetapi konsistensi state lintas executor dan authoritative session source.
2. Jalur hardening RADIUS tetap penting, tetapi replay cache dan disconnect live path sebaiknya tidak diperlakukan sebagai langkah pertama tanpa fondasi session/read model yang benar.
3. Ada gap compliance dan security yang tidak boleh ditunda terlalu lama:
   - audit log vs GDPR erasure model,
   - webhook payment idempotency,
   - ONU admission control.

---

## 3. Temuan Detail

### 3.1 WorkflowJob Split-Brain Lintas Executor

- `Severity`: `High`
- `Verdict`: valid

Spec sudah punya `workflow_jobs`, `workflow_steps`, status `partial`, query `status=inconsistent`, dan endpoint `reconcile`. Itu artinya desain sadar akan partial failure. Masalahnya, spec belum menunjukkan saga orchestration atau compensating action yang eksplisit untuk command lintas `AAA` dan `OLT`.

Evidence:

- `workflow_jobs` dan `workflow_steps` hanya memodelkan status dan retry, belum memodelkan compensation.
- UI bahkan sudah menampilkan contoh state `partial` dengan `failed_step`.
- roadmap infra baru menyebut `retry idempotent`, belum `saga`.

Repo references:

- `docs/modules/oxcore-spec.md:157`
- `docs/modules/oxcore-spec.md:183`
- `docs/modules/oxcore-spec.md:489`
- `docs/architecture/oxion-infra-deployment-spec.md:1480`

Engineering consequence:

- service bisa masuk `desired_state = active` tetapi `actual_state = partial`,
- limbo state akan bergantung pada reconcile berikutnya,
- operator burden naik saat executor berbeda berhasil/gagal secara asimetris.

What is missing:

- command dependency graph yang eksplisit,
- compensating step contract,
- deadline/SLO untuk keluar dari `partial`,
- rule kapan reconcile otomatis vs operator intervention.

### 3.2 RADIUS Session State pada FreeRADIUS DaemonSet

- `Severity`: `High`
- `Verdict`: valid

Spec menyebut FreeRADIUS sebagai `DaemonSet`, sementara active session tracking masih dideskripsikan sebagai `session_tracker` via `ETS`, ditambah cache `Nebulex` TTL 30/300 detik. Itu bukan authoritative session ledger yang meyakinkan untuk `Accounting-Start/Stop`, `Interim-Update`, `CoA`, dan `Disconnect` lintas node.

Repo references:

- `docs/modules/oxradius-spec.md:45`
- `docs/modules/oxradius-spec.md:83`
- `docs/modules/oxradius-spec.md:90`
- `docs/architecture/oxion-infra-deployment-spec.md:33`
- `docs/architecture/oxion-infra-deployment-spec.md:34`
- `docs/architecture/oxion-infra-deployment-spec.md:1155`

Engineering consequence:

- session lookup dapat miss saat traffic accounting dan CoA tidak mendarat di node yang sama,
- cache TTL cocok untuk acceleration, bukan source of truth,
- quota, restore, dan selective disconnect bisa salah target atau tidak menemukan target.

What is missing:

- session read model yang authoritative,
- source of truth accounting/runtime yang jelas,
- rule korelasi session lintas node,
- contract untuk session staleness dan rebuild.

### 3.3 GDPR Right to Erasure vs Append-Only Audit Log

- `Severity`: `High`
- `Verdict`: valid sebagai gap desain; klaim "definitif melanggar" terlalu absolut

Spec sebelumnya menyatakan semua PII bisa dianonymize via `gdpr/erase`, tetapi `audit_log` menyimpan `old_value`, `new_value`, `ip_address`, dan `user_agent`, lalu secara eksplisit dinyatakan append-only tanpa `UPDATE/DELETE`.

Repo references:

- `docs/architecture/oxion-infra-deployment-spec.md:773`
- `docs/architecture/oxion-infra-deployment-spec.md:781`
- `docs/architecture/oxion-infra-deployment-spec.md:1085`
- `docs/architecture/oxion-infra-deployment-spec.md:1086`
- `docs/architecture/oxion-platform-services-spec.md:942`

Interpretation:

- ini tidak otomatis ilegal,
- tetapi saat ini spec belum cukup untuk menjelaskan bagaimana audit PII di-redact, di-hash, di-tokenize, atau dikeluarkan dari identifiable scope,
- tanpa retention basis dan legal basis yang eksplisit, desain compliance-nya bolong.

What is missing:

- model audit payload yang memisahkan PII vs non-PII,
- retention schedule,
- legal basis per field,
- redaction/crypto-shredding/anonymization strategy yang kompatibel dengan append-only semantics.

Target remediation model sekarang didokumentasikan di:

- `docs/implementation/audit-privacy-and-dsr-model.md`

### 3.4 oxRADIUS Fallback Saat oxCore Down

- `Severity`: `Medium`
- `Verdict`: framing awal salah sasaran

Authorize/accounting path di spec bukan `FreeRADIUS -> oxCore`, tetapi `FreeRADIUS -> oxRADIUS Policy API` via `rlm_rest`. Jadi `oxCore` down tidak otomatis memutus auth flow. Yang benar-benar belum dispesifikkan adalah fallback saat `oxRADIUS API`, cache, atau backing data source bermasalah.

Repo references:

- `docs/modules/oxradius-spec.md:27`
- `docs/modules/oxradius-spec.md:45`
- `docs/modules/oxradius-spec.md:134`
- `docs/modules/oxradius-spec.md:145`
- `docs/operations/oxion-dalo-migration-runbook.md:122`

Engineering consequence:

- spec butuh fail-open/fail-close policy untuk authorize path,
- cache semantics harus dijelaskan untuk degraded mode,
- recovery behavior saat `rlm_rest` timeout belum ditulis dengan cukup jelas.

### 3.5 Payment Webhook Idempotency

- `Severity`: `High`
- `Verdict`: valid

Spec oxBill sudah menulis webhook flow dan signature verification, tetapi belum menunjukkan idempotency ledger atau dedupe constraint yang eksplisit untuk event payment provider. Plan MVP bahkan sudah menyebut kebutuhan `duplicate webhook paid test`, yang berarti gap ini memang terbuka.

Repo references:

- `docs/modules/oxbill-spec.md:388`
- `docs/modules/oxbill-spec.md:389`
- `docs/modules/oxbill-spec.md:391`
- `docs/modules/oxbill-spec.md:837`
- `docs/policies/oxion-mvp-fasttrack-plan.md:299`

Engineering consequence:

- satu pembayaran bisa men-trigger aktivasi/restore lebih dari sekali,
- race condition akan merusak audit, workflow job, dan state transition,
- duplicate callback bukan edge case; itu perilaku normal dari banyak provider.

What is missing:

- unique provider event key,
- payment event ledger,
- exactly-once semantics di boundary webhook -> domain event,
- duplicate callback regression test.

### 3.6 ONU Auto-Discovery Tanpa Admission Control

- `Severity`: `High`
- `Verdict`: valid

oxOLT spec bicara auto-discovery dan zero-touch provisioning, tetapi saya tidak menemukan whitelist/allowlist serial/MAC atau approval gate sebelum provisioning. `nas_whitelist` di schema subscriber tidak menyelesaikan problem ONU admission.

Repo references:

- `docs/modules/oxolt-spec.md:23`
- `docs/modules/oxolt-spec.md:283`
- `docs/architecture/oxion-infra-deployment-spec.md:447`

Engineering consequence:

- perangkat yang tidak dikenal bisa ikut masuk jalur provisioning,
- operator dapat salah bind ONU ke layanan,
- attack surface naik untuk unauthorized onboarding dan misbinding VLAN/service profile.

What is missing:

- serial/MAC allowlist,
- staged approval flow,
- inventory reconciliation antara discovered ONU vs assigned service,
- negative tests untuk unknown ONU.

### 3.7 DaemonSet + HPA

- `Severity`: `Low`
- `Verdict`: false positive

Spec memisahkan `oxRADIUS API` yang memakai autoscaling dan `FreeRADIUS` yang sebagai `DaemonSet`. Jadi tidak ada kontradiksi fundamental di deployment model; yang ada hanyalah potensi salah baca karena dua blok ini berdekatan di dokumen.

Repo references:

- `docs/architecture/oxion-infra-deployment-spec.md:1115`
- `docs/architecture/oxion-infra-deployment-spec.md:1155`
- `docs/modules/oxradius-spec.md:352`

Required action:

- perjelas wording dokumen supaya pembaca tidak mengira HPA dipasang ke DaemonSet.

### 3.8 FreeRADIUS ↔ Gleam/BEAM Integration Gap

- `Severity`: `Medium`
- `Verdict`: valid hanya pada level operasional, bukan pada level "mekanisme belum disebut"

Mekanisme integrasi sudah ada dan eksplisit: `rlm_rest` via HTTPS ke oxRADIUS Policy API. Jadi problemnya bukan ketiadaan bridge, melainkan belum cukup detailnya kontrak operasional untuk latency, timeout, retry, degraded mode, dan circuit behavior.

Repo references:

- `docs/modules/oxradius-spec.md:27`
- `docs/modules/oxradius-spec.md:145`
- `docs/operations/oxion-dalo-migration-runbook.md:47`
- `docs/operations/oxion-dalo-migration-runbook.md:122`

What is missing:

- request timeout budget,
- retry policy dan backoff,
- response contract dan failure taxonomy yang lebih preskriptif,
- local fallback semantics bila upstream policy API melambat.

### 3.9 Lite -> Platform Mode Migration

- `Severity`: `High`
- `Verdict`: valid

Spec menekankan satu codebase dengan feature flags, lalu runbook menyederhanakan upgrade ke langkah aktivasi modul dan perpindahan ke Kubernetes. Itu terlalu optimistis. Naik dari Lite ke Platform berarti menyentuh tenancy boundaries, operational routing, storage, secret scope, observability, dan deployment topology.

Repo references:

- `docs/modules/oxradius-spec.md:33`
- `docs/modules/oxradius-spec.md:36`
- `docs/operations/oxion-dalo-migration-runbook.md:171`
- `docs/operations/oxion-dalo-migration-runbook.md:174`
- `docs/architecture/oxion-infra-deployment-spec.md:434`

Engineering consequence:

- migrasi tidak cukup diperlakukan sebagai flag toggle,
- perlu plan data migration dan re-partitioning yang eksplisit,
- perlu rollout/rollback strategy untuk tenancy-aware services.

What is missing:

- migration contract single-tenant -> tenant-aware,
- default tenant extraction/backfill rules,
- unique constraint review,
- config/secrets scoping per tenant/reseller,
- observability dan authorization boundaries untuk multi-tenant mode.

---

## 4. Backlog Implementasi Prioritas

Urutan ini sengaja risk-driven. Tujuannya bukan mengejar checklist paling panjang, tetapi menutup risk dengan rasio nilai tertinggi terlebih dahulu.

### P0 - Fondasi Arsitektur yang Menjadi Gating

1. `Authoritative session read model + NAS endpoint registry`
   - menutup risk `2`
   - menjadi prasyarat nyata untuk `replay cache`, `Disconnect live path`, dan `managed CoA`
   - artefak:
     - `apps/oxradius/src/oxion/radius/session/*`
     - `apps/oxradius/src/oxion/radius/registry/*`
     - adapter pembacaan session runtime dari accounting source

2. `Workflow saga / compensation model untuk lintas AAA dan OLT`
   - menutup risk `1`
   - perlu sebelum orchestration lintas executor dianggap production-safe
   - artefak:
     - state machine `pending/running/partial/compensating/compensated/failed`
     - compensation contract per step
     - reconcile deadline/SLO

3. `Payment webhook idempotency ledger`
   - menutup risk `5`
   - harus berjalan paralel dengan hardening collection/payment recovery
   - artefak:
     - unique provider event key
     - processed webhook ledger
     - duplicate callback tests

### P1 - Security dan Compliance yang Tidak Boleh Ditunda

4. `Audit privacy model untuk GDPR-compatible append-only logging`
  - menutup risk `3`
  - target spec sekarang ada di `docs/implementation/audit-privacy-and-dsr-model.md`
  - artefak:
    - field classification
    - redaction/anonymization strategy
    - retention schedule
     - audit event contract yang meminimalkan raw PII

5. `ONU admission whitelist / approval gate`
   - menutup risk `6`
   - artefak:
     - allowlist serial/MAC
     - pending discovered ONU queue
     - explicit operator approval flow

### P2 - Hardening RADIUS Transport dan Packet Layer

6. `Message-Authenticator + Event-Timestamp + runtime replay cache`
   - melanjutkan hardening packet
   - bergantung pada `P0.1` agar session targeting tidak palsu

7. `Disconnect live path`
   - packet builder, response classifier, live transport, managed execution
   - bergantung pada `P0.1` dan `P2.6`

8. `Vendor dictionary / VSA registry`
   - mengganti prefix-string heuristik
   - bisa paralel sebagian, tetapi paling bernilai setelah transport path cukup stabil

### P3 - Ops dan Future Track

9. `Status-Server + radclient ops tooling`
   - memperjelas health dan operational diagnostics

10. `UDP worker socket reuse`
    - fokus ke throughput dan resource behavior setelah semantics request/reply sudah matang

11. `RadSec transport`
    - penting, tetapi bukan blocker pertama untuk correctness

12. `RADIUS/1.1 tracking`
    - future-facing,
    - jangan dijadikan blocker MVP/Phase D hardening.

### P4 - Spec Clarification Work

13. `Document fallback semantics untuk rlm_rest / oxRADIUS degraded mode`
    - menutup risk `4`

14. `Perjelas pemisahan oxRADIUS HPA vs FreeRADIUS DaemonSet`
    - menutup risk `7`

15. `Perjelas kontrak latency/timeout/retry FreeRADIUS -> oxRADIUS`
    - menutup risk `8`

---

## 5. Rekomendasi Urutan Kerja Praktis

Kalau tujuan langsungnya adalah melanjutkan hardening RADIUS yang sedang dikerjakan di repo ini, urutan paling masuk akal adalah:

1. selesaikan `session read model + NAS registry` sampai bisa menjadi source of truth untuk managed runtime path,
2. definisikan `workflow saga` dan `payment webhook idempotency` sebagai backlog lintas-modul yang harus berjalan paralel,
3. tutup `audit privacy model` dan `ONU admission gate` di level spec sebelum implementasi liar melebar,
4. baru lanjut ke:
   - `replay cache`,
   - `Disconnect live path`,
   - `vendor dictionary / VSA registry`,
5. terakhir masuk ke `ops tooling`, `UDP reuse`, dan `RadSec`.

Kalau urutannya dibalik, kita hanya akan mendapatkan adapter yang lebih canggih secara teknis, tetapi tetap bertumpu pada session state yang tidak authoritative dan orchestration yang masih rawan partial-state limbo.

---

## 6. Sumber Eksternal

Sumber resmi yang relevan untuk review ini:

- Kubernetes Horizontal Pod Autoscaler:
  - `https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/`
- Kubernetes DaemonSet:
  - `https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/`
- FreeRADIUS REST module:
  - `https://www.freeradius.org/documentation/freeradius-server/4.0.0/howto/modules/rest/index.html`
- EDPB right to erasure guidance:
  - `https://www.edpb.europa.eu/node/5347_ga`
- European Commission data subject rights:
  - `https://commission.europa.eu/law/law-topic/data-protection/information-individuals_en`
