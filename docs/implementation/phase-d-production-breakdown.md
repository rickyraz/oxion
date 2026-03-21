# Phase D Production Breakdown

## 1. Tujuan

Dokumen ini memecah **Phase D - RADIUS Path (`radius_only`)** menjadi unit implementasi yang cukup detail untuk dipakai sebagai panduan engineering, estimasi LOC, dan pemecahan folder/module.

Companion docs untuk hardening setelah baseline Phase D:

- `freeradius-interop-standard.md`
- `radius-hardening-roadmap.md`

Dokumen ini melanjutkan baseline yang sudah ada sebelum Phase D:

- contract policy sudah freeze,
- evaluator/simulator sudah deterministic,
- scheduler/dispatcher/idempotency core sudah tersedia.

Phase D adalah titik ketika core policy berhenti menjadi pure function dan mulai bertemu dunia nyata: session aktif, profile aktual di NAS, retry CoA, ACK/NAK, timeout, audit, dan boundary `radius_only` yang tidak boleh bocor ke OLT.

---

## 2. Scope Phase D

Referensi utama: `../policies/oxion-mvp-fasttrack-plan.md`.

Scope resmi phase ini:

1. `oxCore.collection_orchestrator`
2. `oxRADIUS.coa_execution`
3. `oxCore.olt_guard`

Exit criteria phase ini:

- throughput berubah sesuai policy via jalur RADIUS,
- OLT tidak disentuh pada overdue default flow,
- duplicate CoA/action ter-skip dan tetap tercatat.

---

## 3. Baseline yang Sudah Ada

Sebelum Phase D, baseline implementasi Gleam yang sudah dirapikan adalah:

```text
src/
├── oxion.gleam
└── oxion/
    ├── collection/
    │   ├── dispatcher.gleam
    │   ├── idempotency.gleam
    │   └── scheduler.gleam
    └── policy/
        ├── evaluator.gleam
        ├── lifecycle.gleam
        ├── simulator.gleam
        ├── types.gleam
        └── validator.gleam

test/
├── oxion_test.gleam
└── oxion/
    ├── collection/
    │   └── phase_c_test.gleam
    └── policy/
        ├── lifecycle_test.gleam
        └── phase_b_test.gleam
```

Implikasinya:

- `oxion/policy/*` adalah pure policy core.
- `oxion/collection/*` adalah runtime enforcement core yang masih side-effect agnostic.
- Phase D tidak boleh mencampur packet handling ke evaluator atau scheduler.

Kalau boundary ini bocor, codebase akan cepat busuk: policy logic jadi tergantung vendor, dan runtime effect akan sulit dites deterministik.

---

## 4. Organisasi Folder yang Disarankan untuk Phase D

Untuk menjaga boundary tetap jelas, folder target sebaiknya dipisah begini:

```text
src/
├── oxion.gleam
└── oxion/
    ├── collection/
    │   ├── dispatcher.gleam
    │   ├── idempotency.gleam
    │   └── scheduler.gleam
    ├── orchestration/
    │   └── collection/
    │       ├── commands.gleam
    │       ├── orchestrator.gleam
    │       ├── outcome.gleam
    │       ├── audit.gleam
    │       └── olt_guard.gleam
    ├── policy/
    │   ├── evaluator.gleam
    │   ├── lifecycle.gleam
    │   ├── simulator.gleam
    │   ├── types.gleam
    │   └── validator.gleam
    └── radius/
        ├── packet.gleam
        ├── coa/
        │   ├── request.gleam
        │   ├── response.gleam
        │   ├── execution.gleam
        │   ├── retry.gleam
        │   ├── result.gleam
        │   └── transport.gleam
        ├── profile/
        │   ├── types.gleam
        │   ├── resolver.gleam
        │   ├── snapshot.gleam
        │   ├── diff.gleam
        │   └── normalizer.gleam
        └── vendor/
            ├── types.gleam
            ├── cisco.gleam
            ├── juniper.gleam
            └── vbng.gleam

src/
├── oxion_radius_transport_ffi.erl
└── oxion_radius_mock_transport_ffi.erl

test/
├── oxion_test.gleam
└── oxion/
    ├── collection/
    │   └── phase_c_test.gleam
    ├── orchestration/
    │   └── collection/
    │       ├── orchestrator_test.gleam
    │       └── olt_guard_test.gleam
    ├── policy/
    │   ├── lifecycle_test.gleam
    │   └── phase_b_test.gleam
    └── radius/
        ├── coa/
        │   ├── execution_test.gleam
        │   ├── retry_test.gleam
        │   └── result_test.gleam
        └── profile/
            ├── diff_test.gleam
            ├── normalizer_test.gleam
            └── resolver_test.gleam
```

Catatan:

- `policy` tetap pure dan tidak tahu NAS/OLT.
- `collection` tetap bicara intent policy/action, bukan packet RADIUS.
- `orchestration` menerjemahkan intent collection menjadi command domain.
- `radius` memegang detail profile resolution, CoA semantics, retry, ACK/NAK, dan vendor adapter.
- `packet.gleam` memegang codec RADIUS CoA dan verifier authenticator.
- transport UDP nyata diikat via FFI Erlang agar `gen_udp` dan `crypto` tetap keluar dari policy core.

Ini organisasi yang waras. Jangan campur semuanya ke satu file `coa_execution.gleam` raksasa; itu gaya cepat hancur.

---

## 5. D1 - `oxCore.collection_orchestrator`

### 5.1 Tanggung Jawab

`collection_orchestrator` menerima hasil `scheduler + dispatcher`, lalu memutuskan command domain apa yang harus dijalankan pada service inventory / AAA path.

Dia bukan evaluator ulang. Dia juga bukan packet sender.

Input:

- tenant context
- subscriber/service identity
- dispatched actions
- fingerprint/action metadata
- current service state ringkas

Output:

- command list yang ternormalisasi
- audit intent
- operational state transition yang diusulkan
- error/failure classification yang bisa dicatat ke log

### 5.2 File yang Disarankan

1. `src/oxion/orchestration/collection/commands.gleam`
   - type command domain
   - mapping target (`ChangePackage`, `SuspendService`, `RestoreService`)
   - metadata minimum untuk audit
2. `src/oxion/orchestration/collection/orchestrator.gleam`
   - entry point utama phase D dari sisi core orchestration
   - mapping dispatched action -> command plan
3. `src/oxion/orchestration/collection/outcome.gleam`
   - normalized success/fail/skip result
   - result untuk bridge ke audit table / event bus
4. `src/oxion/orchestration/collection/audit.gleam`
   - format audit payload yang konsisten
   - fingerprint, reason, vendor response ringkas, duration, retry count

### 5.3 Type yang Perlu Ada

Minimal type yang realistis:

```gleam
pub type CollectionCommand {
  ChangePackage(service_id: String, target_profile_id: String)
  SuspendService(service_id: String, reason: String)
  RestoreService(service_id: String, original_profile_id: String)
}

pub type CommandPlan {
  CommandPlan(
    action_fingerprint: String,
    stage_id: String,
    action_name: String,
    command: CollectionCommand,
    target_state: String,
  )
}

pub type OrchestrationError {
  UnsupportedAction(action_name: String)
  MissingServiceIdentity
  MissingOriginalProfile
  GuardRejected(reason: String)
}
```

### 5.4 Mapping Rules

1. `apply_bandwidth_profile`
   - map ke `ChangePackage`
   - target state: `throttled_due_overdue`
2. `suspend_service`
   - map ke `SuspendService`
   - target state: `suspended_due_overdue`
3. `restore_service`
   - map ke `RestoreService`
   - target state: `normal`
4. `send_notification`
   - tidak masuk jalur RADIUS execution
   - tetap dicatat sebagai sidecar orchestration ke notification engine
5. `emit_event`
   - tidak masuk jalur CoA
   - route ke event bus terpisah
6. `set_operational_state`
   - tidak boleh langsung override outcome jaringan tanpa hasil enforcement nyata
   - hanya boleh jadi state intent atau metadata, bukan authority final
7. `run_plugin_hook`
   - bukan bagian Phase D default, kecuali dipasang sebagai extensibility hook setelah outcome tersedia

### 5.5 Invariant Penting

- Scheduler boleh match banyak action, tapi orchestrator harus tetap deterministic.
- Satu action policy tidak boleh menghasilkan dua command RADIUS yang saling konflik pada service yang sama.
- `radius_only` berarti orchestration tidak boleh memanggil jalur OLT untuk overdue default.
- Audit tetap ditulis bahkan saat command di-skip.

### 5.6 Failure Taxonomy

`collection_orchestrator` harus membedakan:

- `invalid_intent`
- `guard_rejected`
- `routing_unavailable`
- `execution_failed`
- `idempotent_skip`

Kalau semua error disatukan jadi `failed`, operasi akan buta. Itu cara cepat bikin NOC marah karena semua alert terlihat sama.

### 5.7 Estimasi LOC

- `commands.gleam`: 120-180 LOC
- `orchestrator.gleam`: 250-450 LOC
- `outcome.gleam`: 120-180 LOC
- `audit.gleam`: 120-220 LOC

Subtotal D1:

- minimum serius: 610 LOC
- realistis production-ready: 850-1.050 LOC

### 5.8 Test Minimum

- mapping `apply_bandwidth_profile` -> `ChangePackage`
- mapping `suspend_service` -> `SuspendService`
- unsupported action tidak diam-diam dibuang
- target state mapping konsisten
- duplicate action plan untuk service sama ditolak/dinormalisasi
- audit payload selalu membawa fingerprint dan stage id

---

## 6. D2 - `oxRADIUS.coa_execution`

Ini bagian yang paling mahal. Di sinilah estimasi LOC paling sering diremehkan.

### 6.1 Tanggung Jawab

`coa_execution` bertugas mengeksekusi command RADIUS secara aman dan idempotent.

Fungsi nyatanya bukan sekadar "send packet":

- resolve target profile ke atribut efektif,
- baca snapshot profile aktif/session aktif,
- bandingkan target vs actual,
- skip bila identik,
- bangun CoA request yang vendor-aware,
- kirim packet,
- tangani ACK/NAK/timeout,
- retry terbatas,
- hasilkan outcome yang bisa diaudit.

### 6.2 Pecahan Submodule yang Wajib

#### A. Profile Resolver

File:

- `src/oxion/radius/profile/resolver.gleam`
- `src/oxion/radius/profile/normalizer.gleam`

Tanggung jawab:

- `profile_id` -> effective policy attributes
- flatten policy agar perbandingan tidak bergantung urutan field
- lindungi core dari detail vendor

Masalah yang harus ditangani:

- profile tidak ditemukan
- profile incomplete
- profile deprecated tapi masih terpakai subscriber lama
- profile alias ke profile lain

#### B. Active Snapshot Reader

File:

- `src/oxion/radius/profile/snapshot.gleam`

Tanggung jawab:

- memodelkan snapshot profile/session aktif
- sumber data bisa berasal dari accounting cache, session table, atau adapter query
- hasil harus ternormalisasi sebelum dibandingkan

Masalah yang harus ditangani:

- session tidak aktif
- snapshot stale
- session ganda
- subscriber pindah NAS

#### C. Profile Diff / Idempotency Guard

File:

- `src/oxion/radius/profile/diff.gleam`

Tanggung jawab:

- compare `current_effective_profile` vs `target_effective_profile`
- return `no_change` bila identik
- hasil compare harus stabil walau urutan attribute berbeda

Masalah yang harus ditangani:

- field order mismatch
- duplicate attribute entries
- vendor alias berbeda tapi semantic sama

#### D. CoA Request Builder

File:

- `src/oxion/radius/coa/request.gleam`

Tanggung jawab:

- bangun CoA request RFC 5176 style dari normalized target profile
- masukkan identifier/session selector yang benar
- jaga agar attribute wajib tidak hilang

Masalah yang harus ditangani:

- selector session tidak cukup (`User-Name` saja tidak aman di banyak NAS)
- beberapa vendor butuh kombinasi `Acct-Session-Id`, `NAS-IP-Address`, `Framed-IP-Address`, atau custom key
- beda vendor, beda format attribute

#### E. CoA Response Parser / Result Normalizer

File:

- `src/oxion/radius/coa/response.gleam`
- `src/oxion/radius/coa/result.gleam`

Tanggung jawab:

- parse ACK vs NAK vs malformed reply
- normalize vendor reply ke result yang bisa diandalkan orchestration layer
- simpan vendor reason code bila ada

Masalah yang harus ditangani:

- ACK tanpa semua attribute dipakai benar-benar bukan jaminan profile sudah efektif
- NAK reason berbeda antar vendor
- timeout dan malformed packet harus dibedakan dari NAK

#### F. Retry Policy

File:

- `src/oxion/radius/coa/retry.gleam`

Tanggung jawab:

- backoff policy
- max retry
- retryable vs non-retryable error classification

Masalah yang harus ditangani:

- retry pada NAK bisnis biasanya sia-sia
- retry pada timeout mungkin valid
- retry tanpa correlation ID hanya bikin noise

#### G. Execution Coordinator

File:

- `src/oxion/radius/coa/execution.gleam`

Tanggung jawab:

- entry point `send_coa_if_needed`
- orchestration antara resolver, snapshot, diff, builder, sender, parser, retry, audit result

Ini file paling penting dan paling berisiko jadi monster.

Batas yang sehat:

- coordinator tidak boleh menelan semua detail vendor sendiri
- logika compare profile tidak boleh ditanam di sini
- retry policy jangan ditulis inline di function 400 baris

### 6.3 Type yang Perlu Ada

```gleam
pub type CoaExecutionInput {
  CoaExecutionInput(
    tenant_id: String,
    service_id: String,
    subscriber_id: String,
    target_profile_id: String,
    fingerprint: String,
  )
}

pub type CoaExecutionResult {
  IdempotentSkip(reason: String)
  Ack(applied_profile_id: String, retries: Int)
  Nak(code: String, message: String, retries: Int)
  Timeout(retries: Int)
  SnapshotUnavailable(reason: String)
  ProfileResolutionFailed(reason: String)
}
```

### 6.4 Decision Table `send_coa_if_needed`

1. resolve target profile
   - gagal -> `ProfileResolutionFailed`
2. load active snapshot
   - tidak ada -> tergantung policy runtime: skip, disconnect-only, atau fail explicit
3. normalize current snapshot
4. compare current vs target
   - sama -> `IdempotentSkip`
5. build CoA request
   - gagal -> `execution_failed`
6. send request
7. parse response
   - ACK -> success
   - NAK -> fail dengan vendor reason
   - timeout -> retry jika retryable
8. retry exhausted
   - result terminal + alert signal

### 6.5 Failure Modes yang Wajib Didokumentasikan

- target profile ada tapi tidak kompatibel dengan vendor NAS
- subscriber sudah disconnect saat CoA dikirim
- ACK diterima tapi accounting snapshot belum berubah segera
- duplicate CoA terkirim karena snapshot cache stale
- session selector salah dan CoA mengenai session lain
- NAK vendor karena attribute kombinasi tidak valid
- timeout berulang akibat network path atau secret mismatch

### 6.6 Vendor Adapter Layer

Kalau target benar-benar production-grade, adapter vendor bukan opsional.

Minimal abstraction:

- `vendor/types.gleam`
- `vendor/cisco.gleam`
- `vendor/juniper.gleam`
- `vendor/vbnq.gleam`

Tugas adapter:

- normalize attribute naming
- map target profile ke attribute native
- map reply reason ke taxonomy internal

Jangan letakkan `case vendor` di 15 tempat berbeda. Itu pola murah yang nanti berubah jadi lumpur.

### 6.7 Estimasi LOC

- `profile/resolver.gleam`: 220-380 LOC
- `profile/snapshot.gleam`: 180-300 LOC
- `profile/diff.gleam`: 180-320 LOC
- `profile/normalizer.gleam`: 180-320 LOC
- `coa/request.gleam`: 220-420 LOC
- `coa/response.gleam`: 180-300 LOC
- `coa/result.gleam`: 80-160 LOC
- `coa/retry.gleam`: 120-220 LOC
- `coa/execution.gleam`: 320-520 LOC
- `vendor/*`: 300-900 LOC tergantung jumlah vendor yang diseriusi

Subtotal D2:

- single-vendor ketat: 2.000-2.700 LOC
- multi-vendor production-grade: 2.800-4.000 LOC

### 6.8 Test Minimum

Unit tests:

- profile diff skip jika target == current
- builder menghasilkan request stabil
- malformed snapshot tidak lolos sebagai valid
- NAK parser preserve vendor reason
- retry hanya jalan untuk class error yang benar

Integration-style tests:

- ACK flow sukses tanpa retry
- timeout -> retry -> ACK
- timeout -> retry exhausted
- NAK non-retryable
- stale snapshot tapi target masih sama -> tetap skip
- vendor attribute order berbeda -> compare tetap equal

Fixture tests:

- Cisco mapping
- Juniper mapping
- disaggregated vBNG mapping

---

## 7. D3 - `oxCore.olt_guard`

### 7.1 Tanggung Jawab

`olt_guard` memastikan default overdue enforcement berhenti di jalur RADIUS pada mode `radius_only`.

Ini kelihatan kecil, tapi sifatnya safety rail. Kalau guard ini longgar, satu bug mapping bisa menyentuh OLT dan membuat outage yang tidak perlu.

### 7.2 File yang Disarankan

- `src/oxion/orchestration/collection/olt_guard.gleam`

### 7.3 Rule Minimum

1. Jika mode enforcement = `radius_only`
   - blok semua intent perubahan OLT
2. Jika command berasal dari policy overdue default
   - OLT path tidak boleh disentuh
3. Jika mode explicit nanti diperluas (`radius_plus_olt`, dsb.)
   - guard harus fail closed untuk mode yang belum dikenal

### 7.4 Type Minimum

```gleam
pub type EnforcementTarget {
  RadiusOnly
  RadiusPlusOlt
}

pub type OltGuardError {
  OltMutationBlocked(reason: String)
  UnknownEnforcementTarget(value: String)
}
```

### 7.5 Estimasi LOC

- core guard: 120-180 LOC
- test: 120-180 LOC

Subtotal D3:

- 240-360 LOC

### 7.6 Test Minimum

- `radius_only` memblok OLT mutation
- unknown mode fail closed
- action non-overdue tidak boleh salah diblok kalau memang bukan domain guard ini

---

## 8. Audit, Metrics, dan Observability yang Sudah Harus Dipikirkan di Phase D

Walau dashboard penuh baru ada di Phase G, data dasarnya harus lahir sejak Phase D.

Minimal fields audit yang harus tersedia:

- `tenant_id`
- `service_id`
- `subscriber_id`
- `invoice_id`
- `stage_id`
- `action_name`
- `action_fingerprint`
- `command_name`
- `target_profile_id`
- `current_profile_id`
- `result_type`
- `vendor`
- `vendor_reason_code`
- `retry_count`
- `executed_at`
- `duration_ms`

Minimal metric counter/gauge:

- `collection_radius_coa_attempt_total`
- `collection_radius_coa_ack_total`
- `collection_radius_coa_nak_total`
- `collection_radius_coa_timeout_total`
- `collection_radius_idempotent_skip_total`
- `collection_radius_guard_block_total`

Kalau audit/metric baru dipikirkan setelah runtime hidup, hasilnya biasanya tambal sulam dan root cause analysis jadi siksaan.

---

## 9. Urutan Implementasi yang Masuk Akal

### Slice 1 - Boundary dan command model

Tujuan:

- `orchestration/collection/commands.gleam`
- `orchestration/collection/orchestrator.gleam`
- `orchestration/collection/olt_guard.gleam`

Hasil:

- action policy bisa dipetakan ke command domain tanpa side effect nyata dulu

### Slice 2 - Profile diff dan idempotent skip

Tujuan:

- `radius/profile/{resolver,normalizer,snapshot,diff}.gleam`

Hasil:

- `send_coa_if_needed` belum kirim packet, tapi sudah bisa menjawab `skip vs must_apply`

### Slice 3 - CoA request/result core

Tujuan:

- `radius/coa/{request,response,result}.gleam`

Hasil:

- request/response model jelas, parser dan builder stabil

### Slice 4 - Execution + retry

Tujuan:

- `radius/coa/{retry,execution}.gleam`

Hasil:

- end-to-end runtime `send_coa_if_needed` tersedia

### Slice 5 - Vendor adapters + hardening

Tujuan:

- `radius/vendor/*`
- fixture vendor
- audit enrichment

Hasil:

- production-grade interoperability mulai realistis

Ini urutan yang benar. Kalau langsung lompat ke packet sender sebelum diff/normalizer matang, kamu cuma sedang menabung bug mahal.

---

## 10. Estimasi LOC Total

| Slice | LOC minimum | LOC realistis |
| --- | ---: | ---: |
| D1 orchestrator | 610 | 1.050 |
| D2 coa execution | 2.000 | 4.000 |
| D3 olt guard | 240 | 360 |
| Tests phase D | 1.000 | 2.000 |
| Audit/fixtures glue | 250 | 600 |
| **Total** | **4.100** | **8.010** |

Interpretasi:

- `~4k LOC` adalah versi production-minded tapi masih ketat dan vendor terbatas.
- `~6k-8k LOC` adalah zona yang lebih jujur untuk multi-vendor, retry, fixture, dan audit yang benar.
- kalau mulai menambah admin/reporting/config UI ala `daloRADIUS`, angka ini bukan lagi Phase D. Itu sudah merembet ke phase lain.

---

## 11. Perangkap Scope yang Harus Dihindari

1. Menaruh vendor-specific logic di `policy` atau `collection` core.
2. Menyamakan `ACK` dengan “service state pasti sudah berubah”.
3. Menyamakan `timeout` dengan `NAK`.
4. Menaruh retry loop langsung di file orchestrator.
5. Menganggap `profile_id` compare cukup tanpa normalisasi effective attributes.
6. Mengizinkan overdue default mengubah OLT diam-diam.
7. Menulis satu file `coa_execution.gleam` raksasa yang mengurus segalanya.

Kalau salah satu ini dilakukan, kamu mungkin tetap bisa demo, tapi belum layak disebut production-grade.

---

## 12. Definition of Done Phase D

Phase D baru layak disebut selesai jika semua ini terpenuhi:

- action `apply_bandwidth_profile` dan `suspend_service` benar-benar termapping ke command orchestration
- `send_coa_if_needed` melakukan compare current vs target sebelum kirim packet
- duplicate action/fingerprint tidak menghasilkan CoA ganda
- ACK/NAK/timeout/retry tercatat dengan taxonomy yang konsisten
- `radius_only` guard memblok seluruh mutation path ke OLT untuk overdue default
- test integration `oxBill -> orchestration -> oxRADIUS` tersedia
- audit payload cukup kaya untuk investigasi incident

Kalau belum sampai sini, status yang jujur tetap: **Phase D belum production-grade**.
