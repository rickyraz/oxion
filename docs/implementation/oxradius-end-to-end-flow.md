# oxRADIUS End-to-End Flow

## 1. Tujuan

Dokumen ini menjelaskan alur runtime besar dari:

- `policy`
- `renderer`
- `dictionary`
- `packet`
- `transport`

untuk path `CoA` dan `Disconnect`.

Dokumen ini sengaja diletakkan di `docs/implementation/`, bukan di `docs/modules/` atau `docs/interoperability/`.

Alasannya:

- `docs/modules/` dipakai untuk spec bounded context tingkat modul,
- `docs/interoperability/` dipakai untuk contoh vendor, packet, dan template interop,
- dokumen ini justru menjahit semuanya menjadi flow implementasi nyata lintas submodule.

Dengan kata lain, ini adalah dokumen integrasi runtime, bukan dokumen kontrak modul tunggal.

---

## 2. Scope

Scope dokumen ini adalah path enforcement `oxRADIUS` saat sebuah policy collection menghasilkan command yang harus diterjemahkan menjadi packet RADIUS.

Yang dibahas:

- module mana yang terlibat,
- submodule mana yang memiliki tanggung jawab tertentu,
- kenapa boundary itu dipisah,
- bagaimana alur `CoA` dan `Disconnect` berjalan dari atas ke bawah,
- sejauh mana desain ini selaras dengan RFC,
- apa yang bisa dan tidak bisa diklaim dari sisi GDPR.

Yang tidak dibahas detail di sini:

- admin UI,
- full FreeRADIUS SQL admin plane,
- billing workflow lengkap,
- legal opinion final untuk GDPR.

---

## 3. Letak Modul dan Submodule

Module besar yang terlibat pada flow ini:

1. `oxion/policy`
2. `oxion/collection`
3. `oxion/orchestration/collection`
4. `oxion/radius/profile`
5. `oxion/radius/vendor`
6. `oxion/radius/dictionary`
7. `oxion/radius/packet`
8. `oxion/radius/coa`
9. `oxion/radius/disconnect`
10. `oxion/radius/registry`
11. `oxion/radius/session`
12. `oxion/radius/ops`
13. `oxion/radius/udp`
14. `oxion/radius/radsec`
15. `oxion/radius/protocol`

Submodule dan fungsinya saat ini:

| Layer | Module / Submodule | Tanggung Jawab | Kenapa Dipisah |
| --- | --- | --- | --- |
| Policy | `src/oxion/policy/*` | validasi, evaluasi, simulasi, lifecycle policy | policy engine tidak boleh tahu wire protocol |
| Collection | `src/oxion/collection/*` | scheduling, dispatch, idempotency action | runtime collection tidak boleh tahu detail vendor VSA |
| Orchestration | `src/oxion/orchestration/collection/*` | route command ke AAA / OLT dan bentuk command domain | memisahkan intent bisnis dari adapter teknis |
| Profile | `src/oxion/radius/profile/*` | resolve target profile dan diff dengan state aktif | perubahan profile harus deterministic dan testable |
| Vendor | `src/oxion/radius/vendor/*` | mapping semantic profile ke logical attr vendor | vendor semantics tidak boleh bocor ke packet codec |
| Dictionary | `src/oxion/radius/dictionary/*` | registry logical attr, prefix/value transform, FreeRADIUS naming | wire-format knowledge dikonsolidasikan di satu tempat |
| Packet | `src/oxion/radius/packet.gleam` | code family, authenticator, AVP/VSA encoding, response verification | RFC-specific packet rules jangan menyebar ke renderer |
| CoA | `src/oxion/radius/coa/*` | request/response/result/retry/execution/transport CoA | family `CoA` punya behavior sendiri |
| Disconnect | `src/oxion/radius/disconnect/*` | request/response/result/execution/transport Disconnect | `Disconnect` punya constraints RFC 5176 yang lebih sempit |
| Registry | `src/oxion/radius/registry/*` | resolve NAS endpoint dan capability | secret dan endpoint tidak boleh hardcoded di call site |
| Session | `src/oxion/radius/session/*` | source of truth session aktif / accounting materialization | targeting session harus datang dari runtime state, bukan tebakan caller |
| Ops | `src/oxion/radius/ops/*` | healthcheck, `Status-Server`, radclient tooling | tooling operasional tidak boleh bercampur dengan business path |
| UDP | `src/oxion/radius/udp/*` | worker/socket reuse, socket handle lifecycle, outstanding request tracking | reuse socket adalah concern transport, bukan packet |
| RadSec | `src/oxion/radius/radsec/*` | TLS transport future path | jangan campur UDP logic dengan TLS lifecycle |
| Protocol | `src/oxion/radius/protocol/*` | tracking future protocol evolution | roadmap `RADIUS/1.1` tidak boleh mengotori path MVP |

---

## 4. Diagram Besar

### 4.1 Forward Path

```text
┌───────────────────────────────────────────────────────────────────────────┐
│                           COLLECTION POLICY                              │
│  docs/policies/*                                                         │
│  src/oxion/policy/{types,validator,evaluator,simulator,lifecycle}.gleam │
└───────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ evaluated policy + matched stage
                                   v
┌───────────────────────────────────────────────────────────────────────────┐
│                        COLLECTION RUNTIME                                │
│  src/oxion/collection/{scheduler,dispatcher,idempotency}.gleam           │
└───────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ dispatched action
                                   v
┌───────────────────────────────────────────────────────────────────────────┐
│                     COLLECTION ORCHESTRATION                             │
│  src/oxion/orchestration/collection/{commands,orchestrator,olt_guard,    │
│  outcome,audit}.gleam                                                    │
└───────────────────────────────────────────────────────────────────────────┘
                                   │
                      route == RadiusRoute ? yes
                                   │
                                   v
                 ┌───────────────────────────────────────┐
                 │     MANAGED RUNTIME SIDE INPUTS       │
                 │  src/oxion/radius/session/*           │
                 │  src/oxion/radius/registry/*          │
                 └───────────────────────────────────────┘
                         │                      │
                         │ active session       │ NAS endpoint + capability
                         └──────────┬───────────┘
                                    v
┌───────────────────────────────────────────────────────────────────────────┐
│                      PROFILE AND VENDOR RESOLUTION                       │
│  src/oxion/radius/profile/{resolver,diff,normalizer,types}.gleam        │
│  src/oxion/radius/vendor/{cisco,juniper,vbng,types}.gleam               │
└───────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ logical vendor attributes
                                   v
┌───────────────────────────────────────────────────────────────────────────┐
│                     DICTIONARY AND PACKET LAYER                          │
│  src/oxion/radius/dictionary/{types,registry,encoder,freeradius}.gleam  │
│  src/oxion/radius/packet.gleam                                           │
└───────────────────────────────────────────────────────────────────────────┘
                                   │
                      family == CoA / Disconnect
                                   │
                                   v
┌───────────────────────────────────────────────────────────────────────────┐
│                     FAMILY EXECUTION AND TRANSPORT                       │
│  src/oxion/radius/coa/*                                                  │
│  src/oxion/radius/disconnect/*                                           │
│  src/oxion_radius_transport_ffi.erl                                      │
└───────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ UDP packet
                                   v
┌───────────────────────────────────────────────────────────────────────────┐
│                  FREE RADIUS / NAS / BNG / BRAS / EDGE                   │
└───────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Response Path

```text
NAS / FreeRADIUS response
        │
        v
disconnect.transport / coa.transport
        │
        v
packet.decode_packet(...)
        │
        ├─ verify identifier
        ├─ verify response authenticator
        ├─ verify Message-Authenticator when required
        └─ parse Error-Cause / Reply-Message
        │
        v
disconnect.response / coa.response
        │
        v
disconnect.result / coa.result
        │
        v
orchestration outcome / audit projection
```

### 4.3 Detail Boundary: Renderer ke Wire

```text
vendor renderer
  emits:
    cisco.service_profile = "bw_4mbps"
    cisco.qos_down        = "4096"
    cisco.qos_up          = "4096"

dictionary registry
  owns:
    cisco.service_profile -> Cisco-AVPair + "service_profile="
    cisco.qos_down        -> Cisco-AVPair + "qos_down="
    cisco.qos_up          -> Cisco-AVPair + "qos_up="

dictionary encoder
  builds:
    "service_profile=bw_4mbps"
    "qos_down=4096"
    "qos_up=4096"

packet layer
  wraps:
    RADIUS code + identifier + authenticator + AVP/VSA bytes

transport
  sends:
    UDP roundtrip with timeout / retry / live socket path
```

---

## 5. Kenapa Boundary Ini Lebih Baik

### 5.1 Policy Tidak Tahu Packet

Kalau `policy` tahu `Cisco-AVPair` atau `ERX-Dynamic-Profile-Name`, policy engine akan ikut rusak setiap kali vendor mapping berubah.

Boundary yang benar:

- `policy` hanya menentukan intent,
- `orchestration` menentukan route dan command,
- `radius` adapter menentukan bagaimana intent itu menjadi protocol side effect.

### 5.2 Vendor Renderer Tidak Tahu Wire Prefix

Renderer vendor sekarang mengeluarkan logical name seperti:

- `cisco.service_profile`
- `juniper.profile_name`
- `vbng.profile_id`

bukan prefix lama seperti:

- `cisco_avpair.service_profile`
- `dynamic_profile.name`
- `api.policy.profile_id`

Ini lebih baik karena:

- renderer mengekspresikan semantic attr, bukan string hack,
- dictionary layer yang memiliki pengetahuan tentang `value_prefix`,
- packet layer tinggal mengubah logical attr menjadi wire bytes.

### 5.3 Dictionary Menjadi Single Source of Encoding Truth

`src/oxion/radius/dictionary/*` adalah tempat yang paling benar untuk menyimpan:

- logical name,
- vendor id,
- vendor type,
- allowed packet family,
- value prefix,
- FreeRADIUS dictionary name.

Satu hal penting:

- beberapa logical attr memang sengaja jatuh ke physical VSA yang sama,
- contoh: `cisco.service_profile`, `cisco.qos_down`, dan `cisco.qos_up` semuanya tetap memakai `Cisco-AVPair`,
- yang membedakan ketiganya adalah `value_prefix`, bukan nama physical VSA.

Kalau informasi ini disebar ke renderer dan packet layer sekaligus, hasilnya cepat menjadi split-brain.

### 5.4 Packet dan Transport Tidak Boleh Disatukan

`packet.gleam` mengurus:

- RFC code family,
- AVP/VSA encoding,
- request/response authenticator,
- `Message-Authenticator`,
- `Event-Timestamp`,
- response verification.

`transport` mengurus:

- host/port/secret resolution yang sudah disiapkan,
- timeout,
- retry loop,
- live UDP roundtrip,
- response mapping ke result domain.

Kalau dua lapisan ini dicampur, test menjadi mahal dan bug sulit diisolasi.

---

## 6. Diagram Per Family

### 6.1 CoA

```text
CommandPlan(ChangePackage / SuspendService)
        │
        v
profile.resolver.resolve_plan_target(...)
        │
        v
vendor.render_profile(...) / vendor.render_suspend(...)
        │
        v
coa.request.build_request(...)
        │
        v
packet.encode_coa_request_with_security(...)
        │
        v
coa.transport.prepare_roundtrip(...)
        │
        v
coa.transport.roundtrip_prepared(...)
        │
        v
coa.response.{Ack,Nak,Timeout,TransportError}
        │
        v
coa.result.*
```

### 6.2 Disconnect

```text
CommandPlan(SuspendService)
        │
        v
disconnect.request.build_request(...)
        │
        v
packet.encode_disconnect_request_with_security(...)
        │
        v
disconnect.transport.prepare_roundtrip(...)
        │
        v
disconnect.transport.roundtrip_prepared(...)
        │
        v
disconnect.response.{Ack,Nak,Timeout,TransportError}
        │
        v
disconnect.result.*
```

Perbedaan penting:

- `CoA` boleh membawa authorization change attrs,
- `Disconnect` hanya boleh membawa NAS dan session identification attrs sesuai RFC 5176.

---

## 7. Status Terhadap RFC

### 7.1 Ringkasan

Kalau implementasi mengikuti boundary di dokumen ini, maka arah desainnya sudah benar terhadap RFC.

Tapi itu bukan berarti semua RFC sudah selesai 100 persen.

Statusnya lebih tepat seperti ini:

| Area | Status | Catatan |
| --- | --- | --- |
| RFC 2865 base packet model | Mostly aligned | packet structure, identifier, authenticator, endpoint registry model sudah searah |
| RFC 2866 accounting/session correlation | Partially aligned | `Acct-Session-Id` sudah jadi selector penting, tapi authoritativeness tetap bergantung pada read model runtime |
| RFC 2869 `Message-Authenticator` / `Event-Timestamp` | Mostly aligned | support sudah ada, tapi enforcement bersama lintas semua family dan worker belum final |
| RFC 5080 retransmission / duplicate handling | Partially aligned | replay model sudah dipakai pada managed `CoA` dan `Disconnect`, tetapi UDP worker/shared runtime enforcement belum final |
| RFC 5176 CoA / Disconnect separation | Mostly aligned | builder `CoA` dan `Disconnect` sudah terpisah, packet family juga terpisah |
| RFC 5997 Status-Server | Partially aligned | live smoke path dan response verification sudah ada, tetapi inventory target dan diagnostics masih belum final |
| RFC 6613 / 6614 TCP/TLS / RadSec | Not complete | baru scaffold |
| RFC 6929 extended vendor model | Partial groundwork | dictionary/VSA registry sudah lebih baik, tapi coverage vendor belum lengkap |
| RFC 9765 RADIUS/1.1 | Future track only | masih tracking, bukan implementation target sekarang |

### 7.2 Yang Sudah Benar Secara Arsitektur

Hal berikut sudah benar kalau mengikuti file ini:

1. secret dan endpoint diselesaikan di registry/runtime layer, bukan dari attr di packet,
2. `CoA` dan `Disconnect` dibangun dengan path berbeda,
3. packet verification berada di packet layer, bukan di renderer,
4. vendor semantic attr dipisah dari wire encoding,
5. session targeting berada di session/read-model layer, bukan dicampur ke policy.

### 7.3 Yang Masih Harus Dikerjakan

Hal berikut belum boleh diklaim selesai penuh:

1. replay protection shared runtime lintas worker UDP dan family lain di luar managed boundary sekarang,
2. worker-driven default path dan concurrency scheduler di atas UDP reuse yang baru,
3. richer `Status-Server` inventory target dan diagnostics,
4. `RadSec` live path,
5. vendor dictionary coverage yang lebih lengkap,
6. vBNG live transport yang benar-benar supported.

---

## 8. Status Terhadap GDPR

### 8.1 Jawaban Pendek

Tidak. Mengikuti dokumen ini saja tidak otomatis membuat sistem menjadi GDPR-compliant.

Yang benar:

- desain ini membantu data minimization dan boundary hygiene,
- tetapi GDPR compliance tetap membutuhkan kontrol hukum, operasional, dan data lifecycle yang lebih luas.

### 8.2 Kenapa Tidak Otomatis Cukup

Flow `policy -> renderer -> dictionary -> packet -> transport` hanya menjawab:

- bagaimana data enforcement diterjemahkan ke packet,
- bagaimana side effect ke NAS dibuat lebih deterministic,
- bagaimana secret, session, dan wire encoding dipisah dengan benar.

Flow ini belum dengan sendirinya menjawab:

- dasar hukum pemrosesan,
- retention period,
- erasure workflow,
- DSR handling,
- audit log privacy model,
- log redaction / anonymisation / crypto-shredding,
- propagasi penghapusan ke sistem eksternal.

### 8.3 Yang Sudah Membantu GDPR

Arsitektur ini tetap berguna untuk GDPR karena:

1. data semantic dipisah dari wire payload,
2. packet layer hanya membawa attr yang memang dibutuhkan untuk enforcement,
3. session dan endpoint resolution dapat dibatasi pada data operasional minimum,
4. vendor encoding tidak memaksa policy layer mengetahui detail identitas jaringan yang tidak relevan bagi business rule.

### 8.4 Yang Masih Wajib Ada

Kalau target pasar mencakup EU, maka selain flow teknis ini kamu masih perlu:

1. data inventory dan classification yang jelas,
2. retention schedule per data class,
3. proses erasure atau restriction yang terdokumentasi,
4. dasar hukum untuk audit retention,
5. treatment khusus untuk append-only audit log,
6. mekanisme pseudonymisation, redaction, atau crypto-shredding bila relevan,
7. SOP penanganan data subject request,
8. propagation plan ke processor atau downstream system.

### 8.5 Hal Penting dari Sumber Resmi

Berdasarkan sumber resmi EU:

- right to erasure bukan hak absolut,
- organisasi dapat menolak erasure dalam kasus terbatas seperti kewajiban hukum, public interest tertentu, atau kebutuhan untuk legal claims,
- data tidak boleh disimpan tanpa batas; retention harus dibatasi oleh tujuan dan kewajiban hukum yang relevan.

Implikasi untuk repo ini:

- append-only audit log tidak otomatis ilegal,
- tetapi tidak boleh dibiarkan tanpa privacy model, retention rule, dan dasar hukum yang jelas.

Dokumen ini adalah engineering guidance, bukan legal advice.

---

## 9. Rekomendasi Praktis

Urutan yang paling sehat setelah mengikuti flow ini:

1. teruskan `Status-Server` dan ops tooling,
2. perluas dictionary/VSA registry,
3. bangun `RadSec`,
4. selesaikan audit privacy model dan DSR workflow di layer platform yang relevan.

Kalau dibalik, transport akan terlihat makin canggih tapi fondasi compliance dan runtime correctness tetap bolong.

---

## 10. Referensi

RFC dan sumber resmi yang relevan:

- [RFC 2865](https://www.rfc-editor.org/rfc/rfc2865)
- [RFC 2866](https://www.rfc-editor.org/rfc/rfc2866)
- [RFC 2869](https://www.rfc-editor.org/rfc/rfc2869)
- [RFC 5080](https://www.rfc-editor.org/rfc/rfc5080)
- [RFC 5176](https://www.rfc-editor.org/rfc/rfc5176)
- [RFC 5997](https://www.rfc-editor.org/rfc/rfc5997)
- [RFC 6613](https://www.rfc-editor.org/rfc/rfc6613)
- [RFC 6614](https://www.rfc-editor.org/rfc/rfc6614)
- [RFC 6929](https://www.rfc-editor.org/rfc/rfc6929)
- [RFC 9765](https://www.rfc-editor.org/rfc/rfc9765)
- [EDPB: Respect individuals’ rights](https://www.edpb.europa.eu/sme-data-protection-guide/respect-individuals-rights_en)
- [European Commission: Do we always have to delete personal data if a person asks?](https://commission.europa.eu/law/law-topic/data-protection/rules-business-and-organisations/dealing-citizens/do-we-always-have-delete-personal-data-if-person-asks_en)
- [European Commission: Information for individuals](https://commission.europa.eu/law/law-topic/data-protection/information-individuals_en)
- [European Commission: For how long can data be kept?](https://commission.europa.eu/law/law-topic/data-protection/rules-business-and-organisations/principles-gdpr/how-long-can-data-be-kept-and-it-necessary-update-it_en)
