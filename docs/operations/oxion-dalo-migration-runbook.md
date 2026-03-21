# Oxion daloRADIUS Migration Runbook

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](../architecture/oxion-infra-deployment-spec.md)
- [Platform Services Specification](../architecture/oxion-platform-services-spec.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)
- [Oxion Docs Map](../README.md)

---

## 2. Tujuan

Runbook ini menjelaskan langkah migrasi dari instalasi daloRADIUS (umumnya MySQL/MariaDB) ke Oxion dengan risiko minimal dan rollback yang jelas.

Target hasil:

- Operasional AAA tetap berjalan selama cutover.
- Data inti subscriber/NAS/accounting termigrasi tervalidasi.
- Deployment awal memakai **Lite Mode**, lalu dapat di-upgrade ke **Platform Mode**.

---

## 3. Ruang Lingkup Data

Objek migrasi inti:

- `radcheck`
- `radreply`
- `radusergroup`
- `nas`
- `radacct`

Objek tambahan (opsional):

- `userinfo` / tabel custom lokal
- konfigurasi voucher custom
- atribut vendor-specific non-standar

---

## 4. Prasyarat

- Akses read ke database daloRADIUS (MySQL/MariaDB).
- Backup terbaru database sumber.
- Environment Oxion Lite siap (Docker Compose) dan health check lulus.
- Kredensial FreeRADIUS `rlm_rest` untuk endpoint Oxion sudah disiapkan.
- Jadwal maintenance window dan PIC rollback ditetapkan.

---

## 5. Checklist Pra-Migrasi

- [ ] Konfirmasi versi DB sumber dan ukuran tabel utama.
- [ ] Inventaris custom attribute/VSA yang dipakai aktif.
- [ ] Inventaris jenis autentikasi aktif (PAP/CHAP/MS-CHAP/EAP/MAB/Voucher).
- [ ] Snapshot backup DB sumber tersimpan dan teruji restore.
- [ ] Snapshot backup environment target (Oxion + FreeRADIUS config) dibuat.
- [ ] Definisikan tenant default untuk data hasil import.
- [ ] Definisikan mapping role/operator awal.

---

## 6. Langkah Migrasi (Dry-Run Dulu)

### 6.1 Validasi Koneksi Sumber

```http
POST /v1/migration/dalo/validate-connection
```

Checklist:

- [ ] Koneksi sukses.
- [ ] Jumlah tabel inti terdeteksi lengkap.

### 6.2 Preview Mapping

```http
POST /v1/migration/dalo/preview-mapping
```

Checklist:

- [ ] Mapping field sesuai ekspektasi.
- [ ] Unknown attribute dicatat untuk keputusan manual.

### 6.3 Dry-Run Import

```http
POST /v1/migration/dalo/dry-run
```

Checklist:

- [ ] Total record source vs target cocok (dengan toleransi yang disetujui).
- [ ] Sample subscriber login test lulus di staging.
- [ ] Tidak ada error kritikal pada VSA/attribute parser.

---

## 7. Cutover Produksi

### 7.1 Freeze Window

- [ ] Bekukan perubahan admin di panel lama.
- [ ] Umumkan start maintenance ke tim operasi.

### 7.2 Import Final

```http
POST /v1/migration/dalo/import
```

Checklist:

- [ ] Import final selesai tanpa error kritikal.
- [ ] Integritas data subscriber/NAS tervalidasi.

### 7.3 Switch Traffic

- [ ] FreeRADIUS diarahkan ke endpoint Oxion (`rlm_rest`) target.
- [ ] Uji autentikasi login sukses untuk akun aktif.
- [ ] Uji accounting start/stop dan update interim.

### 7.4 Smoke Test Operasional

- [ ] CRUD subscriber.
- [ ] Disconnect/CoA.
- [ ] Generate/redeem voucher.
- [ ] Monitoring metrik auth error dan latency.

---

## 8. Rollback Plan

Trigger rollback bila salah satu terjadi:

- auth failure rate melewati ambang yang disepakati,
- login massal gagal,
- accounting tidak tercatat konsisten.

Langkah rollback:

1. Kembalikan endpoint FreeRADIUS ke backend lama.
2. Jalankan endpoint rollback migrasi:

```http
POST /v1/migration/dalo/rollback
```

3. Restore snapshot target bila diperlukan.
4. Umumkan rollback selesai dan lakukan RCA.

---

## 9. Validasi Pasca-Migrasi

- [ ] 24 jam auth success rate stabil.
- [ ] Latency authorize sesuai SLO.
- [ ] Accounting records masuk normal.
- [ ] Tidak ada gap data kritikal dari sample audit.
- [ ] Operator helpdesk dapat menjalankan flow harian tanpa blocker.

---

## 10. Jalur Upgrade ke Platform Mode

Setelah Lite stabil:

1. Aktifkan feature flags lanjutan per tenant.
2. Aktifkan modul oxCore/oxBill/oxNOC bertahap.
3. Pindahkan operasi dari single VM ke Kubernetes.
4. Konsolidasi penuh ke PostgreSQL 18 sebagai source of truth.

---

## 11. Artefak yang Harus Disimpan

- Log hasil `validate-connection`, `preview-mapping`, `dry-run`, `import`.
- Snapshot ID backup sumber dan target.
- Hasil smoke test + metrik 24 jam pasca-cutover.
- Catatan issue dan keputusan mapping manual.
