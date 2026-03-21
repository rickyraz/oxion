# Broadband Packet-Level Validation Checklist

## 1. Dokumen Terkait

- [Tier-1 Broadband Interop Profile](./oxion-tier1-broadband-interoperability-profile.md)
- [RADIUS Access-Accept and CoA Examples](./radius-access-coa-examples.md)
- [NAS Vendor Mapping Template](./nas-vendor-mapping-template.md)

---

## 2. Tujuan

Checklist ini untuk validasi packet-level di lab/UAT agar flow RADIUS/NAS/QoS sesuai desain Oxion.

---

## 3. Persiapan Test

- [ ] Topologi tersedia: ONT/OLT -> Aggregation -> NAS/BNG -> RADIUS.
- [ ] Capture point disiapkan (SPAN/tcpdump) di sisi NAS <-> RADIUS.
- [ ] Subscriber test account dan profile baseline tersedia.
- [ ] Policy collection published dan active di tenant uji.
- [ ] NTP/timezone sinkron di semua node.

---

## 4. Baseline Session Validation

## 4.1 Access-Request / Access-Accept

- [ ] Access-Request diterima RADIUS dengan identifier/session selector valid.
- [ ] Access-Accept mengandung profile normal (service_profile + up/down rate).
- [ ] NAS apply QoS baseline sesuai profile normal.

Evidence minimum:

- Packet capture request/response pair.
- Log NAS bahwa subscriber profile berhasil diterapkan.

## 4.2 Accounting Lifecycle

- [ ] Accounting-Start terkirim setelah session up.
- [ ] Accounting-Interim terkirim sesuai interval policy.
- [ ] Accounting-Stop terkirim saat session terminate.

---

## 5. Overdue Enforcement Validation

## 5.1 Soft Throttle (CoA)

- [ ] Event overdue memicu evaluasi policy stage soft throttle.
- [ ] CoA-Request dikirim dengan target profile throttled.
- [ ] CoA-ACK diterima.
- [ ] Throughput test menunjukkan limit baru (mis. 4 Mbps).

## 5.2 Hard Suspend

- [ ] Stage hard suspend memicu CoA/disable action.
- [ ] Session dibatasi/ditutup sesuai capability NAS.
- [ ] Subscriber tidak dapat trafik internet normal.

---

## 6. Restore Validation (Paid)

- [ ] Event `invoice.paid` diterima sistem.
- [ ] CoA restore dikirim ke NAS.
- [ ] Profile kembali ke baseline normal.
- [ ] `operational_state` kembali `normal`.

---

## 7. Idempotency Validation

- [ ] Kirim ulang event overdue yang sama -> action kedua ter-skip.
- [ ] Tidak ada CoA duplikat untuk target profile yang sama.
- [ ] `collection_enforcement_log` mencatat `idempotent_skip`.

---

## 8. Failure/NAK Validation

- [ ] Simulasikan CoA-NAK dari NAS.
- [ ] Sistem mencatat reason vendor.
- [ ] Retry berjalan sesuai policy terbatas.
- [ ] Alert ops terbit setelah retry habis.

---

## 9. Boundary Validation (`radius_only`)

- [ ] Selama overdue flow, tidak ada perubahan profile OLT.
- [ ] Service VLAN/ONT config OLT tetap sama.
- [ ] Semua perubahan enforcement terjadi di NAS/RADIUS path.

---

## 10. Multi-Overdue Conflict Validation

- [ ] Siapkan subscriber dengan >1 invoice overdue aktif.
- [ ] Evaluator memakai `days_past_due` tertinggi (worst-case precedence).
- [ ] Restore tidak terjadi bila masih ada overdue aktif lain.

---

## 11. Sign-Off Criteria

- [ ] Semua checklist critical pass.
- [ ] Evidence capture tersimpan (pcap + logs + metrics).
- [ ] Mapping vendor profile yang dipakai tercatat (Cisco/Juniper/vBNG).
- [ ] Catatan deviasi dan workaround terdokumentasi.
