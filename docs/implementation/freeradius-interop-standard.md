# FreeRADIUS Interop Standard

## 1. Tujuan

Dokumen ini merangkum baseline standar interoperabilitas yang harus diikuti untuk membuat adapter RADIUS / FreeRADIUS yang layak dipakai di lingkungan ISP, terutama untuk path `CoA` dan `Disconnect`.

Dokumen ini bukan blueprint admin panel. Fokusnya adalah:

- contract operasional adapter,
- aturan RFC yang relevan,
- detail FreeRADIUS yang harus dihormati,
- area yang wajib dipisahkan dari policy core.

Dokumen ini melengkapi:

- `docs/implementation/phase-d-production-breakdown.md`
- `docs/implementation/radius-hardening-roadmap.md`

---

## 2. Prinsip Boundary

Boundary yang harus dijaga:

- policy core tidak tahu tabel FreeRADIUS,
- policy core tidak tahu packet codec,
- orchestration tidak tahu detail socket,
- transport tidak boleh menyimpan business rule overdue,
- inventory/runtime adapter boleh membaca data FreeRADIUS, tapi tidak menjadi source of truth policy.

Yang boleh diadopsi dari pola daloRADIUS:

- konsep inventory `nas`,
- compatibility layer untuk schema/version,
- operational tooling (`radclient`, `status`),
- bootstrap/init yang idempotent.

Yang tidak boleh diadopsi mentah:

- shared-DB model sebagai domain source of truth,
- business rule collection di `radreply`/`radcheck`,
- campur admin plane, reporting plane, dan enforcement plane ke satu lapisan runtime.

---

## 3. RFC Baseline

### 3.1 RFC 2865 - RADIUS Base

Hal yang relevan untuk adapter:

- packet RADIUS memakai `Code`, `Identifier`, `Length`, `Authenticator`, dan attributes.
- shared secret dipilih dari source IP packet, bukan dari `NAS-IP-Address`.
- `NAS-IP-Address` dan `NAS-Identifier` adalah attributes identifikasi, bukan secret selector.

Implikasi implementasi:

- registry endpoint harus keyed by transport/source identity, bukan oleh attr di dalam packet.
- response validator harus memverifikasi identifier dan authenticator.

Referensi:

- [RFC 2865](https://datatracker.ietf.org/doc/html/rfc2865)

### 3.2 RFC 2866 - Accounting

Hal yang relevan:

- `Acct-Session-Id` adalah korelator session penting.
- Accounting `Start` dan `Stop` harus memakai `Acct-Session-Id` yang sama.

Implikasi:

- read model session harus bisa resolve session lewat `Acct-Session-Id`.
- snapshot runtime jangan terus bergantung pada input magis dari caller.

Referensi:

- [RFC 2866](https://www.rfc-editor.org/rfc/rfc2866)

### 3.3 RFC 2869 / RFC 3579 - Message-Authenticator dan Event-Timestamp

Hal yang relevan:

- `Message-Authenticator` adalah attr `80`.
- `Event-Timestamp` adalah attr `55`.
- `RFC 3579` membuat `Message-Authenticator` wajib saat ada `EAP-Message`.

Implikasi:

- walau Phase D tidak memproses EAP, packet layer harus punya encoder/decoder `Message-Authenticator`.
- `Event-Timestamp` sebaiknya tersedia di request hardening path.

Referensi:

- [RFC 2869](https://www.rfc-editor.org/rfc/rfc2869)
- [RFC 3579](https://datatracker.ietf.org/doc/html/rfc3579)

### 3.4 RFC 5080 - Implementation Practices

Hal yang relevan:

- retransmission harus memakai backoff dan jitter yang waras,
- duplicate detection harus jelas,
- identifier tidak boleh direuse sembarangan,
- implementasi modern disarankan menguatkan `Message-Authenticator`.

Implikasi:

- retry policy tidak cukup berupa angka delay yang dihitung lalu dibuang,
- harus ada outstanding request table dan duplicate/replay model.

Referensi:

- [RFC 5080](https://datatracker.ietf.org/doc/html/rfc5080)

### 3.5 RFC 5176 - Dynamic Authorization Extensions

Hal yang relevan:

- `Disconnect-Request`, `Disconnect-ACK`, `Disconnect-NAK`
- `CoA-Request`, `CoA-ACK`, `CoA-NAK`
- UDP dynamic authorization default port `3799`
- request harus memuat session identification yang memadai
- `Disconnect-Request` hanya boleh memuat NAS dan session identification attrs
- `Error-Cause(101)` harus diparsing
- `Event-Timestamp` direkomendasikan untuk replay protection

Implikasi:

- builder `CoA` dan `Disconnect` harus dipisah, jangan satu list attr generik.
- validator response harus mengerti `Error-Cause`.
- replay window wajib dimodelkan.

Referensi:

- [RFC 5176](https://datatracker.ietf.org/doc/html/rfc5176)

### 3.6 RFC 5997 - Status-Server

Hal yang relevan:

- `Status-Server` adalah packet health-check standar RADIUS.
- request ini wajib punya `Message-Authenticator`.
- request ini tidak boleh diproxy/forward sembarangan.

Implikasi:

- health tooling sebaiknya tidak bikin packet custom liar,
- gunakan `Status-Server` untuk liveness/readiness bila NAS atau proxy mendukung.

Referensi:

- [RFC 5997](https://datatracker.ietf.org/doc/html/rfc5997)

### 3.7 RFC 6613 / RFC 6614 - TCP dan TLS

Hal yang relevan:

- `RFC 6613` adalah RADIUS over TCP,
- `RFC 6614` adalah RADIUS over TLS / RadSec.

Implikasi:

- istilah `socket pool` lebih relevan untuk TCP/TLS dibanding UDP,
- untuk secret rotation dan koneksi jangka panjang, TLS adalah jalur yang lebih matang daripada menekan UDP terus.

Referensi:

- [RFC 6613](https://datatracker.ietf.org/doc/html/rfc6613)
- [RFC 6614](https://datatracker.ietf.org/doc/html/rfc6614)

### 3.8 RFC 6929 - Extended Attributes

Hal yang relevan:

- extended attributes dan EVS penting untuk vendor matrix yang lebih rapi.

Implikasi:

- registry VSA tidak boleh selamanya berhenti di prefix-string klasik.

Referensi:

- [RFC 6929](https://datatracker.ietf.org/doc/html/rfc6929)

### 3.9 RFC 9765 - RADIUS/1.1

Hal yang relevan:

- `RADIUS/1.1` adalah arah baru untuk TLS-based transport tanpa warisan MD5 lama.
- statusnya masih `Experimental`.

Implikasi:

- jangan jadikan dependency MVP,
- tapi desain transport layer sebaiknya tidak memblokir migrasi ke jalur ini.

Referensi:

- [RFC 9765](https://www.rfc-editor.org/rfc/rfc9765)

---

## 4. FreeRADIUS Baseline

### 4.1 Client Definitions

Detail FreeRADIUS yang relevan:

- client biasanya didefinisikan dengan `ipaddr`, `secret`, dan knobs keamanan tambahan.
- ada opsi `require_message_authenticator`.
- ada opsi `limit_proxy_state`.
- dokumentasi FreeRADIUS menyarankan memakai IP ketimbang hostname untuk client definitions.

Implikasi:

- registry adapter harus menyimpan IP endpoint sebagai primary runtime value.
- hardening knobs seperti `require_message_authenticator` dan `limit_proxy_state` layak dimodelkan di endpoint capability/config.

Referensi:

- [FreeRADIUS `clients.conf`](https://www.freeradius.org/documentation/freeradius-server/4.0.0/reference/raddb/clients.conf.html)

### 4.2 SQL Module dan Standard Tables

Detail yang relevan:

- FreeRADIUS SQL module punya jalur standar untuk `radacct`, `radpostauth`, `nas`, dan tabel AAA lain.

Implikasi:

- session read model dan compatibility layer harus dibangun di atas adapter yang memahami SQL schema FreeRADIUS.
- policy core tetap tidak boleh bicara ke tabel itu secara langsung.

Referensi:

- [FreeRADIUS SQL module](https://www.freeradius.org/documentation/freeradius-server/4.0.0/reference/raddb/mods-available/sql.html)

### 4.3 Dictionary Model

Detail yang relevan:

- FreeRADIUS dictionary model eksplisit: `ATTRIBUTE`, `VALUE`, `VENDOR`, `BEGIN-VENDOR`, `END-VENDOR`.

Implikasi:

- vendor registry internal sebaiknya meniru model eksplisit ini,
- bukan menurunkan wire encoding dari prefix string semata.

Referensi:

- [FreeRADIUS dictionaries](https://www.freeradius.org/documentation/freeradius-server/4.0~alpha1/reference/dictionary/index.html)

### 4.4 Originate CoA

Detail yang relevan:

- FreeRADIUS punya contoh originate CoA dan eksplisit menyebut bahwa vendor docs menentukan attr apa saja yang perlu dibawa di packet.

Implikasi:

- vendor capability matrix wajib memisahkan:
  - selector attrs,
  - authorization change attrs,
  - attrs yang legal untuk CoA,
  - attrs yang legal untuk Disconnect.

Referensi:

- [FreeRADIUS originate CoA](https://www.freeradius.org/documentation/freeradius-server/4.0.0/reference/raddb/sites-available/originate-coa.html)

### 4.5 Operational Tools

Detail yang relevan:

- `radclient` didokumentasikan sebagai tool untuk auth, accounting, CoA, Disconnect, dan debug packet.

Implikasi:

- ops tooling internal sebaiknya membungkus `radclient` atau menyediakan fitur yang setara untuk smoke/UAT.

Referensi:

- [FreeRADIUS radclient](https://www.freeradius.org/documentation/freeradius-server/4.0.0/howto/optimization/tools/radclient.html)

---

## 5. Contract Operasional yang Direkomendasikan

### 5.1 NAS Registry

Entity minimum yang direkomendasikan:

```text
NasEndpoint {
  tenant_id: String
  endpoint_id: String
  vendor: RadiusVendor
  transport: Udp | RadSec
  source_match: IpOrCidr
  nas_identifier: Option(String)
  coa_host: String
  coa_port: Int
  secret_ref: SecretRef
  timeout_ms: Int
  retransmit_profile_id: String
  require_message_authenticator: Bool
  require_event_timestamp: Bool
  status_server_enabled: Bool
  capabilities: NasCapabilities
}
```

Aturan:

- secret tidak disimpan raw di domain layer,
- capability vendor dibaca dari registry, bukan di-hardcode ke scheduler,
- registry harus adapter-bound per tenant/vendor/NAS.

### 5.2 Session Read Model

Entity minimum yang direkomendasikan:

```text
ActiveSession {
  tenant_id: String
  service_id: String
  username: Option(String)
  acct_session_id: Option(String)
  framed_ip: Option(String)
  nas_ip_address: Option(String)
  nas_identifier: Option(String)
  active_profile_id: Option(String)
  last_accounting_at: Timestamp
  session_active: Bool
}
```

Aturan:

- snapshot policy runtime harus berasal dari read model ini,
- fallback selector order harus eksplisit dan dites,
- accounting freshness window harus ada.

### 5.3 Dictionary/VSA Registry

Entity minimum yang direkomendasikan:

```text
RadiusAttributeSpec {
  logical_name: String
  protocol_family: Standard | Vsa | Evs
  radius_type: Int
  vendor_id: Option(Int)
  vendor_type: Option(Int)
  data_type: String | Integer | IpV4 | IpV6 | Octets | Tlv
  allowed_in: Access | Accounting | CoA | Disconnect
  role: Selector | AuthorizationChange | ReplyOnly | AccountingOnly
  freeradius_name: String
  source_ref: String
}
```

Aturan:

- attr selector tidak boleh otomatis dipakai sebagai change attr,
- attr yang unsupported harus fail-closed,
- registry harus bisa map ke nama dictionary FreeRADIUS.

---

## 6. Rekomendasi Normatif untuk Repo Ini

### 6.1 Wajib untuk Phase D Hardening

Wajib dibangun:

1. `NAS endpoint registry`
2. `Message-Authenticator`
3. `Event-Timestamp`
4. replay / duplicate cache
5. `Disconnect-Request`
6. explicit vendor dictionary registry
7. session read model

### 6.2 Jangan Dikerjakan Terbalik

Yang sering salah:

- membangun TLS/RadSec dulu saat endpoint registry belum ada,
- menambah banyak vendor prefix sebelum dictionary registry ada,
- memakai read model manual permanen,
- menaruh retry di domain tanpa scheduler transport nyata.

### 6.3 Inference Operasional

Ini adalah inference engineering dari standar dan docs di atas:

- untuk implementasi baru, kirim `Message-Authenticator` di semua `CoA` dan `Disconnect`, walau RFC lama tidak selalu memaksakannya untuk setiap packet.
- gunakan IP literal untuk endpoint primer; hostname hanya opsional dan butuh refresh strategy.
- perlakukan UDP `socket reuse` sebagai worker socket + outstanding request table, bukan `connection pool` ala TCP.
- simpan separation yang tegas antara:
  - policy engine,
  - session/read model,
  - packet codec,
  - transport runtime,
  - ops tooling.

---

## 7. Mapping ke Struktur Repo

Modul yang disarankan untuk langkah berikutnya:

```text
src/oxion/radius/
├── registry/
│   ├── types.gleam
│   ├── resolver.gleam
│   └── capability.gleam
├── session/
│   ├── types.gleam
│   ├── resolver.gleam
│   └── compatibility.gleam
├── dictionary/
│   ├── types.gleam
│   ├── registry.gleam
│   ├── encoder.gleam
│   └── freeradius.gleam
├── coa/
│   ├── request.gleam
│   ├── response.gleam
│   ├── execution.gleam
│   ├── retry.gleam
│   ├── result.gleam
│   └── transport.gleam
└── ops/
    ├── status.gleam
    ├── healthcheck.gleam
    └── radclient.gleam
```

Boundary:

- `registry/*` dan `session/*` adalah adapter/runtime support,
- `dictionary/*` adalah interoperabilitas wire-format,
- `coa/*` adalah packet + execution path,
- `ops/*` adalah tool operasional.

---

## 8. Penutup

Implementasi Phase D saat ini sudah lebih rapi secara arsitektur daripada wrapper tradisional yang langsung menabrakkan logic ke database atau script.

Tetapi untuk benar-benar layak disebut transport subsystem FreeRADIUS yang matang, baseline di dokumen ini harus dipenuhi terlebih dahulu.
