# Radius Hardening Roadmap

## 1. Tujuan

Dokumen ini memecah langkah lanjutan setelah Phase D baseline supaya adapter CoA/Disconnect bergerak dari:

- `real UDP transport`

menjadi:

- `production-ready interoperability subsystem`

Dokumen ini fokus pada urutan kerja, artefak yang perlu dibuat, dan definisi selesai per workstream.

Dokumen ini melengkapi:

- `phase-d-production-breakdown.md`
- `freeradius-interop-standard.md`
- `architecture-risk-review.md`

---

## 2. Status Saat Ini

Baseline yang sudah ada di repo:

- packet codec dasar untuk `CoA`
- live UDP send/receive via Erlang FFI
- response authenticator verification
- pure-domain path dan live path yang terpisah
- vendor renderer dasar (`Cisco`, `Juniper`, `vBNG`)

Gap yang masih tersisa:

- belum ada `NAS endpoint registry`,
- belum ada `Message-Authenticator`,
- belum ada `Event-Timestamp` dan replay cache,
- belum ada `Disconnect-Request`,
- vendor VSA masih terlalu heuristik,
- belum ada session read model dari FreeRADIUS runtime,
- belum ada health tooling,
- belum ada RadSec path.

Scaffold baseline yang sudah ditanam di repo untuk workstream berikutnya:

- `src/oxion/radius/registry/*`
- `src/oxion/radius/coa/replay.gleam`
- `src/oxion/radius/disconnect/*`
- `src/oxion/radius/dictionary/*`
- `src/oxion/radius/session/*`
- `src/oxion/radius/ops/*`
- `src/oxion/radius/udp/*`
- `src/oxion/radius/radsec/*`
- `src/oxion/radius/protocol/tracking.gleam`

Catatan:

- scaffold ini sengaja belum menyatakan workstream selesai,
- yang ditanam sekarang adalah type contract, resolver dasar, helper packet awal, dan test baseline agar implementasi berikutnya tidak mulai dari nol.

Progress yang sudah benar-benar terhubung sesudah scaffold awal:

- packet layer sudah mengenal code family `Disconnect`
- packet layer sudah punya helper `Message-Authenticator` dan `Event-Timestamp`
- encoder dictionary sudah mulai dipakai oleh packet translation path
- live `CoA` path sudah bisa dibangun dari `NAS registry + session read model` via managed execution path
- session compatibility layer sudah bisa mematerialisasi `ActiveSession` dari accounting-style records
- endpoint resolution pada managed path sekarang mempertahankan `nas_identifier`, bukan hanya `nas_ip_address`
- replay cache sudah terhubung ke managed `CoA` runtime path sebagai state input/output yang eksplisit
- `Disconnect` sekarang punya live transport dan managed execution path dengan prepared-request seam yang setara secara pola dengan `CoA`

Yang masih belum selesai penuh:

- `Message-Authenticator` belum diterapkan ke seluruh packet family di semua jalur transport
- replay cache baru terhubung ke managed `CoA` path dan belum menjadi shared runtime enforcement lintas `Disconnect` atau worker UDP
- `Disconnect` belum terhubung ke replay/runtime enforcement yang sama dengan `CoA`
- vendor registry belum menggantikan semua prefix mapping legacy
- `Status-Server`, `UDP worker`, dan `RadSec` masih berupa baseline contract

---

## 3. Urutan Implementasi

Urutan yang direkomendasikan:

1. `NAS registry + runtime config`
2. `Message-Authenticator + Event-Timestamp + replay/duplicate cache`
3. `Disconnect-Request/ACK/NAK`
4. `vendor dictionary/VSA registry`
5. `session read model + compatibility layer`
6. `Status-Server + radclient ops tooling`
7. `UDP worker socket reuse`
8. `RadSec transport`
9. `RADIUS/1.1 tracking`

Jangan dibalik.

Kalau vendor registry dan session source belum ada, memperkeras transport saja hanya membuat adapter lebih cepat salah.

---

## 3.1 Penyesuaian Prioritas Berdasarkan Risk Review

`architecture-risk-review.md` menambah satu koreksi penting terhadap urutan kerja yang kelihatannya murni teknis.

Walau replay cache, disconnect live path, dan VSA registry tetap wajib, ada dua fondasi yang harus diperlakukan sebagai gating work sebelum hardening packet dilanjutkan terlalu jauh:

1. `session read model` yang benar-benar authoritative,
2. `NAS endpoint registry` yang menjadi runtime source of truth.

Alasannya sederhana:

- replay protection tanpa session source yang benar hanya membuat packet path lebih ketat, bukan lebih benar,
- disconnect live path tanpa endpoint/session resolution yang tepercaya hanya memindahkan bug dari layer orchestration ke wire protocol,
- VSA registry akan memberi payoff jauh lebih besar setelah target session dan NAS resolution sudah deterministic.

Workstream lintas modul yang harus berjalan paralel:

- `workflow saga / compensation` di `oxCore`,
- `payment webhook idempotency` di `oxBill`,
- `audit privacy model` dan `ONU admission gate` di spec/domain masing-masing.

Dengan kata lain, backlog berikut tetap benar secara teknis, tetapi secara prioritas eksekusi harus dibaca bersama risk review.

---

## 4. Workstream A - NAS Registry dan Runtime Config

### 4.1 Target

Menghilangkan dependency pada config manual `host/port/secret` per call dan menggantinya dengan endpoint registry yang bisa di-resolve per tenant/vendor/NAS/session context.

### 4.2 Artefak yang Disarankan

```text
src/oxion/radius/registry/types.gleam
src/oxion/radius/registry/resolver.gleam
src/oxion/radius/registry/capability.gleam
test/oxion/radius/registry/resolver_test.gleam
```

### 4.3 Type Minimum

```gleam
pub type TransportKind {
  Udp
  RadSec
}

pub type NasCapabilities {
  NasCapabilities(
    supports_coa: Bool,
    supports_disconnect: Bool,
    supports_status_server: Bool,
    requires_message_authenticator: Bool,
    requires_event_timestamp: Bool,
    supports_multi_session_match: Bool,
  )
}

pub type NasEndpoint {
  NasEndpoint(
    tenant_id: String,
    endpoint_id: String,
    vendor: vendor_types.RadiusVendor,
    transport: TransportKind,
    coa_host: String,
    coa_port: Int,
    secret_ref: String,
    timeout_ms: Int,
    retry_profile_id: String,
    nas_identifier: option.Option(String),
    capabilities: NasCapabilities,
  )
}
```

### 4.4 Rules

- resolve endpoint berdasarkan tenant + session selector + vendor.
- `nas_identifier` hanya selector, bukan secret key.
- IP literal adalah primary runtime endpoint.
- fallback matching rules harus eksplisit dan terdokumentasi.

### 4.5 Definition of Done

- live transport tidak lagi menerima secret raw dari caller domain.
- endpoint resolution deterministic dan dites.
- failure mode untuk unknown NAS fail-closed.

---

## 5. Workstream B - Message-Authenticator, Event-Timestamp, Replay Cache

### 5.1 Target

Menaikkan packet support dari baseline `Request/Response Authenticator` menjadi packet integrity dan replay model yang lebih layak.

### 5.2 Artefak yang Disarankan

```text
src/oxion/radius/packet.gleam
src/oxion/radius/coa/transport.gleam
src/oxion/radius/coa/replay.gleam
test/oxion/radius/packet_test.gleam
test/oxion/radius/coa/transport_test.gleam
```

### 5.3 Pekerjaan Inti

1. encode/decode `Message-Authenticator`
2. encode/decode `Event-Timestamp`
3. request builder yang tahu packet type dan attr order yang benar
4. replay cache keyed by:
   - endpoint
   - identifier
   - request authenticator
   - timestamp window
5. duplicate response guard

### 5.4 Rules

- implementasi baru harus mengirim `Message-Authenticator` untuk `CoA` dan `Disconnect`.
- response validator harus memverifikasi `Message-Authenticator` bila hadir.
- packet tanpa `Event-Timestamp` harus bisa:
  - ditolak,
  - atau diperingatkan,
  - tergantung capability endpoint.

### 5.5 Definition of Done

- ada test positif dan negatif untuk `Message-Authenticator`
- ada test replay/stale packet
- timeout dan retry tidak lagi hanya menghitung delay lalu mengabaikannya

---

## 6. Workstream C - Disconnect Path

### 6.1 Target

Menambah packet family `Disconnect-Request/ACK/NAK` sebagai path enforcement yang berbeda dari `CoA`.

### 6.2 Artefak yang Disarankan

```text
src/oxion/radius/disconnect/request.gleam
src/oxion/radius/disconnect/response.gleam
src/oxion/radius/disconnect/execution.gleam
test/oxion/radius/disconnect/request_test.gleam
test/oxion/radius/disconnect/execution_test.gleam
```

### 6.3 Rules

- `Disconnect-Request` builder hanya boleh menerima session/NAS identifiers.
- attr perubahan profile tidak boleh lolos ke packet ini.
- response classification harus memetakan `Disconnect-ACK` vs `Disconnect-NAK`.

### 6.4 Definition of Done

- code path `Disconnect` terpisah dari `CoA`
- builder menolak attr yang tidak legal
- live transport test untuk `Disconnect-ACK` dan `Disconnect-NAK` tersedia

---

## 7. Workstream D - Vendor Dictionary / VSA Registry

### 7.1 Target

Mengganti prefix-string heuristik menjadi registry eksplisit berbasis vendor dictionary.

### 7.2 Artefak yang Disarankan

```text
src/oxion/radius/dictionary/types.gleam
src/oxion/radius/dictionary/registry.gleam
src/oxion/radius/dictionary/encoder.gleam
src/oxion/radius/dictionary/freeradius.gleam
test/oxion/radius/dictionary/registry_test.gleam
test/oxion/radius/dictionary/encoder_test.gleam
```

### 7.3 Data Minimum

Setiap attribute spec minimal punya:

- logical name
- protocol family (`Standard`, `Vsa`, `Evs`)
- type id
- vendor id
- vendor type
- data type
- allowed packet families
- role (`Selector`, `AuthorizationChange`, `ReplyOnly`, `AccountingOnly`)
- FreeRADIUS dictionary name
- reference source

### 7.4 Rules

- attr selector dan attr perubahan policy harus dibedakan.
- attr unsupported fail-closed.
- renderer vendor hanya menghasilkan logical attrs; encoder yang mengubahnya menjadi wire format.

### 7.5 Definition of Done

- packet layer tidak lagi menebak attr dari prefix string
- vendor renderer tidak lagi menulis wire encoding langsung
- registry bisa dipakai untuk dokumentasi interop dan packet validation

---

## 8. Workstream E - Session Read Model dan Compatibility Layer

### 8.1 Target

Menghapus ketergantungan pada `ActiveProfileSnapshot` yang berasal dari input liar dan menggantinya dengan read model runtime yang konsisten.

### 8.2 Artefak yang Disarankan

```text
src/oxion/radius/session/types.gleam
src/oxion/radius/session/resolver.gleam
src/oxion/radius/session/compatibility.gleam
test/oxion/radius/session/resolver_test.gleam
```

### 8.3 Source Data

Source yang layak dipakai:

- `radacct`
- `radpostauth`
- `nas`

### 8.4 Rules

- compatibility layer menangani variasi schema/version.
- core policy tidak membaca SQL schema langsung.
- freshness window untuk session aktif harus ada.

### 8.5 Definition of Done

- `send_coa_live` dapat bekerja dari session read model tanpa snapshot manual
- unknown/stale session diklasifikasi jelas
- compatibility tests untuk schema mapping ada

---

## 9. Workstream F - Ops Tooling

### 9.1 Target

Menyediakan tooling operasional yang tidak mencemari business logic.

### 9.2 Artefak yang Disarankan

```text
src/oxion/radius/ops/status.gleam
src/oxion/radius/ops/healthcheck.gleam
src/oxion/radius/ops/radclient.gleam
test/oxion/radius/ops/healthcheck_test.gleam
```

### 9.3 Fungsi Minimum

- `Status-Server` health check
- smoke `radclient` wrapper
- transport diagnostics
- error classification yang bisa dipakai runbook/UAT

### 9.4 Definition of Done

- endpoint health bisa diuji tanpa menjalankan policy runtime penuh
- ops path punya output yang bisa dipakai untuk UAT dan incident response

---

## 10. Workstream G - UDP Worker Socket Reuse

### 10.1 Target

Mengganti model `open-send-recv-close` per packet dengan worker socket reuse yang lebih waras.

### 10.2 Artefak yang Disarankan

```text
src/oxion_radius_transport_ffi.erl
src/oxion/radius/coa/transport.gleam
test/oxion/radius/coa/transport_test.gleam
```

### 10.3 Rules

- worker socket di-bind eksplisit
- outstanding request table per worker
- identifier allocator tidak bentrok
- response source validation ketat

### 10.4 Definition of Done

- retry tidak memerlukan socket baru per attempt
- concurrent request behavior deterministic dan dites

---

## 11. Workstream H - RadSec

### 11.1 Target

Menambah jalur TLS untuk transport yang lebih matang dan lebih siap untuk secret rotation / long-lived transport.

### 11.2 Artefak yang Disarankan

```text
src/oxion/radius/radsec/types.gleam
src/oxion/radius/radsec/transport.gleam
src/oxion/radius/radsec/certs.gleam
test/oxion/radius/radsec/transport_test.gleam
```

### 11.3 Rules

- TLS config harus adapter-bound
- cert bootstrap tidak boleh masuk policy core
- health tooling harus bisa membedakan error TLS vs error RADIUS packet

### 11.4 Definition of Done

- endpoint registry bisa memilih `Udp` atau `RadSec`
- integration test untuk connect / reconnect / certificate failure tersedia

---

## 12. Workstream I - RADIUS/1.1 Tracking

### 12.1 Target

Menjaga desain tetap siap migrasi ke jalur baru tanpa membuat MVP tersandera eksperimen.

### 12.2 Rules

- jangan hardcode asumsi bahwa semua transport berbasis MD5 authenticator klasik
- abstractions packet integrity dan transport security dipisah
- tidak perlu dikerjakan sebelum UDP + RadSec matang

---

## 13. Checklist Implementasi

Checklist pendek yang bisa dipakai sebagai gate:

- [ ] endpoint registry tersedia
- [ ] secret lookup tidak lagi raw/manual
- [ ] `Message-Authenticator` tersedia
- [ ] `Event-Timestamp` tersedia
- [ ] replay cache tersedia
- [ ] `Disconnect-Request` tersedia
- [ ] dictionary/VSA registry tersedia
- [ ] session read model tersedia
- [ ] `Status-Server` tersedia
- [ ] worker socket reuse tersedia
- [ ] RadSec tersedia

---

## 14. Penutup

Urutan di dokumen ini sengaja keras.

Kalau implementation order dibalik, hasilnya biasanya jelek:

- transport makin kompleks,
- interop tetap rapuh,
- vendor handling tetap liar,
- session targeting tetap tidak bisa dipercaya.

Jalur yang benar adalah:

1. tentukan endpoint dan capability,
2. tentukan session target,
3. tentukan attr legal,
4. baru kirim packet yang dikeraskan,
5. lalu tambah ops dan TLS.
