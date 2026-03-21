# Oxion Tier-1 Broadband Interoperability Profile

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](./oxion-infra-deployment-spec.md)
- [oxCore Spec](./oxcore-spec.md)
- [oxRADIUS Spec](./oxradius-spec.md)
- [oxOLT Spec](./oxolt-spec.md)
- [Platform Services Specification](./oxion-platform-services-spec.md)
- [RADIUS Access-Accept and CoA Examples](./radius-access-coa-examples.md)
- [NAS Vendor Mapping Template](./nas-vendor-mapping-template.md)
- [Broadband Packet Validation Checklist](./broadband-packet-validation-checklist.md)

---

## 2. Tujuan

Dokumen ini mendefinisikan profil interoperabilitas Oxion untuk skenario broadband tier-1 (model FTTH GPON/XGS-PON) dengan glue system:

- OLT (akses fiber)
- NAS/BNG (session + QoS/policy)
- RADIUS/AAA (authz + accounting + CoA)

Fokus utama: kompatibel dengan pola operator besar (termasuk pola modern AT&T Fiber) tanpa mengunci ke satu vendor.

---

## 3. Scope Arsitektur Glue

Alur referensi:

1. ONT/ONU attach ke OLT (PON access).
2. Traffic OLT di-uplink ke aggregation -> NAS/BNG.
3. NAS/BNG create session (IPoE atau PPPoE).
4. NAS query RADIUS (`Access-Request`).
5. RADIUS return policy (`Access-Accept` + attrs).
6. NAS apply profile/QoS.
7. Event billing (overdue/lunas) memicu CoA (`RFC 5176`) ke NAS.
8. NAS update policy realtime (tanpa wajib disconnect).

Catatan MVP Oxion:

- Overdue enforcement default: `radius_only`.
- OLT tidak diubah untuk overdue path default.

---

## 4. Access Mode Profile

| Mode | Status Oxion | Catatan |
| --- | --- | --- |
| IPoE (DHCP-based broadband) | Primary profile tier-1 | Cocok untuk operator modern skala besar |
| PPPoE | Supported | Umum pada banyak ISP regional/legacy |

Rekomendasi deploy tier-1:

- Jadikan IPoE sebagai default profile.
- PPPoE tetap disediakan untuk market yang memerlukan.

---

## 5. Vendor Interop Matrix (Target)

| Layer | Vendor/Platform | Status Target Oxion | Catatan Implementasi |
| --- | --- | --- | --- |
| OLT | Nokia (ALU) | Supported profile | GPON/XGS-PON multi-market |
| OLT | Ericsson | Supported profile | Integrasi via adapter vendor |
| OLT | Calix/Adtran | Supported profile | Mode operator-specific templates |
| OLT | **Huawei (MA5600T/MA5800)** | **Priority profile** | Service-port, VLAN profile, ONT profile mapping |
| OLT | **ZTE (C300/C600)** | **Priority profile** | ONU service profile + traffic profile mapping |
| NAS/BNG | Cisco (ASR/NCS/8000) | Supported profile | VSA/AVPair mapping per policy |
| NAS/BNG | Juniper MX | Supported profile | Dynamic profile/policer per subscriber |
| NAS/BNG | Disaggregated vBNG | Supported profile | API/adapter-driven enforcement |
| AAA | FreeRADIUS hybrid + Gleam | Core design | CoA, accounting, policy runtime |

---

## 6. Huawei & ZTE OLT Profile Notes

## Huawei OLT (MA5600T/MA5800)

- Mapping utama:
  - ONT/ONU discovery -> inventory binding
  - service-port/VLAN profile -> service intent Oxion
  - line/service profile -> package baseline access
- Verifikasi wajib:
  - ONU state sync
  - optical level baseline
  - service-port consistency after reprovision

## ZTE OLT (C300/C600)

- Mapping utama:
  - ONU profile + T-CONT/GEM mapping
  - traffic/service profile binding
  - VLAN translation/QinQ profile
- Verifikasi wajib:
  - service profile drift detection
  - ONU auth/provision sync
  - rollback profile saat reconcile failure

---

## 7. Detail Glue RADIUS -> NAS/BNG -> QoS

## 7.1 Peran Komponen

- **RADIUS/AAA**: autentikasi, otorisasi profile, accounting, CoA command source.
- **NAS/BNG**: terminasi session subscriber (IPoE/PPPoE), enforcement QoS/policer/queue.
- **QoS Engine (di NAS/BNG)**: menerapkan profile bandwidth dan policy shaping realtime.

Prinsip kunci:

- OLT tetap layer akses.
- Perubahan speed/suspend default dilakukan di NAS/BNG via RADIUS attributes + CoA.

## 7.2 Session Lifecycle (IPoE dan PPPoE)

### IPoE (tier-1 default)

1. Subscriber DHCP discover/request.
2. NAS/BNG trigger AAA lookup ke RADIUS (`Access-Request`).
3. RADIUS balas `Access-Accept` + policy attrs.
4. NAS buat subscriber session + apply QoS profile.
5. Accounting Start/Interim/Stop dikirim ke RADIUS.

### PPPoE

1. PPPoE discovery + session setup.
2. PAP/CHAP auth ke RADIUS.
3. `Access-Accept` + profile attrs.
4. NAS apply queue/policer.
5. Accounting lifecycle berjalan sama.

## 7.3 Policy Mapping Model (Vendor-Agnostic -> Vendor-Specific)

Internal model Oxion (source of truth):

- `service_profile_id`
- `download_kbps`, `upload_kbps`
- `session_policy` (allow/suspend/quarantine)
- `accounting_policy` (interim interval, counters)

Adapter translation (`nas_vendor_profile`):

- Standard attrs untuk baseline kompatibilitas.
- VSA/AVPair khusus vendor untuk enforcement optimal.
- Fallback otomatis jika attr vendor tertentu tidak tersedia.

## 7.4 RADIUS Attribute Profile (Konseptual)

| Kategori | Contoh Nilai | Tujuan |
| --- | --- | --- |
| Session control | session timeout / idle timeout | kontrol lifecycle session |
| Addressing | framed IP / pool hint | assign IP subscriber |
| QoS baseline | up/down rate profile | shaping utama |
| QoS dynamic | CoA rate update attrs | perubahan speed realtime |
| Accounting | interim interval / class tag | billing + observability |
| Access action | permit / suspend / quarantine | enforcement status layanan |

Catatan: format final attr ditentukan per vendor adapter (Cisco/Juniper/vBNG), bukan hardcoded di core.

## 7.5 QoS Enforcement Behavior

Mode default Oxion untuk collection:

- **soft stage**: ganti ke profile throttled (mis. `bw_4mbps`) via CoA.
- **hard stage**: suspend session via AAA policy (dengan opsi disconnect).
- **restore**: kembali ke profile normal via CoA.

Rule runtime:

- `send_coa_if_needed` wajib compare profile aktif vs target profile.
- Jika sama, action dicatat sebagai `idempotent_skip`.
- Jika berbeda, kirim CoA update.

## 7.6 State Machine QoS pada NAS

- `normal` -> `throttled_due_overdue`
- `throttled_due_overdue` -> `suspended_due_overdue`
- `throttled_due_overdue` -> `normal` (paid)
- `suspended_due_overdue` -> `normal` (paid)

State ini harus konsisten dengan `operational_state` di oxCore.

---

## 8. CoA Behavior Profile (RFC 5176)

## 8.1 Skenario Wajib

1. **Throttle overdue**
   - Billing policy match -> CoA update bandwidth profile.
2. **Hard suspend**
   - Stage suspend -> disable/suspend via AAA path.
3. **Restore after paid**
   - Invoice paid -> CoA restore original profile.

## 8.2 Retry and Timeout Rules

- CoA timeout -> retry terbatas dengan backoff.
- Setelah retry habis -> emit alert + tandai action failed.
- Duplicate event tidak boleh memicu repeated enforcement (fingerprint check).

## 8.3 Ack/Nak Handling

- **CoA-ACK**: action success, update enforcement log.
- **CoA-NAK**: action failed, simpan reason code vendor, kirim alert ops.

---

## 9. NAS Vendor Profile (QoS Mapping)

| NAS/BNG | Mapping Umum | Catatan |
| --- | --- | --- |
| Cisco BNG | AVPair/VSA profile + policy-map hint | gunakan adapter normalizer untuk varian platform |
| Juniper MX BNG | dynamic profile + policer binding | enforce via subscriber profile abstraction |
| Disaggregated vBNG | API/agent-based policy apply | wajib dukung CoA-equivalent semantics |

Kaidah utama:

- Oxion core hanya kirim intent (`apply_bandwidth_profile`, `suspend_service`, `restore_service`).
- Nas adapter bertanggung jawab mapping ke format native vendor.

---

## 10. Interop Test Matrix Minimum

- IPoE flow: Access-Request -> Accept -> Accounting Start/Interim/Stop.
- PPPoE flow: auth + profile apply + reconnect behavior.
- CoA apply/ack/timeout behavior per NAS vendor.
- Overdue stage progression + paid restore.
- OLT untouched assertion untuk mode `radius_only`.
- Huawei/ZTE provisioning reconcile after policy change.
- Idempotent skip verification saat target profile = active profile.
- Multi-overdue precedence check (worst `days_past_due` wins).

---

## 11. Implementasi Oxion (Boundary yang Wajib Dijaga)

- `oxCore`: intent orchestration + adapter routing.
- `oxRADIUS`: policy decision + AAA + CoA emission path.
- `oxOLT`: access provisioning/inventory/reconcile.
- `oxBill`: collection policy decision source (publish/simulate/runtime).

Boundary rule:

- Overdue policy default berhenti di RADIUS path (`radius_only`), bukan mengubah OLT profile.
- OLT enforcement hanya aktif bila policy target eksplisit mengarah ke OLT/Both.

---

## 12. Non-Goals Dokumen Ini

- Tidak menetapkan command CLI vendor secara hardcoded.
- Tidak mengunci satu vendor sebagai sumber kebenaran.
- Tidak memuat detail internal deployment operator tertentu.
