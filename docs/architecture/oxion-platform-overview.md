# Oxion — ISP Operating Platform

> **Tagline:** One Platform. Every ISP Operation.

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](oxion-infra-deployment-spec.md)
- [Platform Services Specification](oxion-platform-services-spec.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)
- [oxCore Spec](../modules/oxcore-spec.md)
- [oxOLT Spec](../modules/oxolt-spec.md)
- [oxBill Spec](../modules/oxbill-spec.md)
- [oxNOC Spec](../modules/oxnoc-spec.md)
- [Open-Core Boundary](open-core-boundary.md)
- [Brand Naming](oxion-brand-naming.md)
- [Plugin Architecture](../plugins/oxion-plugin-architecture.md)

---

## 2. Product Family

| Modul | Nama | Fungsi |
|---|---|---|
| AAA & Policy Engine | **oxRADIUS** | Autentikasi, otorisasi, akuntansi berbasis FreeRADIUS + Gleam |
| OLT & Fiber Management | **oxOLT** | Manajemen perangkat OLT, ONU lifecycle, VLAN, provisioning |
| Orchestrator & Service Inventory | **oxCore** | Control plane ISP — orkestrasi, source of truth layanan |
| Monitoring & Dashboard | **oxNOC** | Real-time monitoring, alerting, observabilitas penuh |
| Billing & Payment | **oxBill (EE)** | Invoice, voucher, payment gateway, prepaid/postpaid |

---

## 3. Proposal Proyek

Oxion adalah platform operasional ISP generasi berikutnya yang dirancang untuk menyatukan seluruh lapisan infrastruktur jaringan, autentikasi, dan bisnis dalam satu control plane terpadu. Platform ini lahir dari kebutuhan nyata operator ISP yang selama ini harus mengelola tiga sistem terpisah secara manual — sistem AAA/RADIUS untuk autentikasi pelanggan, sistem OLT untuk manajemen perangkat fiber optik, dan sistem ERP/billing untuk proses bisnis — dengan konsekuensi tingginya risiko inkonsistensi state, lambatnya waktu respons operasional, serta beban koordinasi antar tim yang tidak efisien. Oxion hadir sebagai jawaban atas fragmentasi tersebut dengan menghadirkan arsitektur berbasis orchestrator yang menjadikan seluruh sistem eksisting sebagai executor, sementara keputusan bisnis dan teknis dikendalikan terpusat melalui satu antarmuka yang kohesif. Dengan pendekatan self-hosted dan kemampuan white-label, Oxion dapat di-deploy di infrastruktur milik operator sendiri sekaligus dijual kembali kepada mitra ISP sebagai platform bermerek milik mereka.

Untuk kebutuhan adopsi bertahap, Oxion disiapkan dalam dua profil operasi dengan codebase yang sama. **Lite Mode** menargetkan skenario kecil seperti panel FreeRADIUS klasik (setara pengalaman awal daloRADIUS) dengan instalasi cepat di satu VM dan menu inti operasional. Ketika kebutuhan bertambah, operator dapat beralih ke **Platform Mode** untuk mengaktifkan multi-tenant, orchestration, observability penuh, dan deployment cloud-native tanpa migrasi ulang produk.

Komponen inti Oxion terdiri dari lima modul yang saling terintegrasi namun dapat di-deploy secara independen sesuai kebutuhan operator. Modul **oxRADIUS** dibangun di atas FreeRADIUS 3.2.x dengan lapisan logika kebijakan yang ditulis menggunakan bahasa pemrograman Gleam di atas BEAM Virtual Machine, menghadirkan keunggulan konkurensi aktor, toleransi kesalahan melalui OTP supervision tree, serta keamanan tipe data pada waktu kompilasi yang tidak ditemukan pada solusi AAA konvensional. Modul **oxOLT** menyediakan manajemen lifecycle ONU secara penuh — mulai dari auto-discovery, konfigurasi service profile dan line profile, manajemen VLAN dan GEMPORT, hingga monitoring sinyal optik berbasis SNMP — dengan dukungan vendor MikroTik, Huawei, ZTE, dan DOCSIS CMTS. Modul **oxCore** berperan sebagai otak platform, menerima intent bisnis dari sistem ERP seperti Odoo dan menerjemahkannya menjadi execution plan yang dijalankan secara idempotent ke oxRADIUS dan oxOLT. Modul **oxNOC** menghadirkan observabilitas penuh melalui integrasi Prometheus, Grafana, Loki, dan Tempo, sementara modul **oxBill** menangani seluruh siklus billing mulai dari pembuatan invoice PDF otomatis, manajemen voucher, hingga integrasi payment gateway lokal dan internasional.

Dari sisi arsitektur teknis, Oxion mengimplementasikan pola pemisahan yang ketat antara intent bisnis, desired state, execution, dan actual state. Setiap operasi — baik aktivasi layanan, suspensi akibat tagihan jatuh tempo, maupun terminasi kontrak — direpresentasikan sebagai `WorkflowJob` dengan `WorkflowStep` yang dapat di-retry secara individual dan bersifat idempotent. Service Inventory dalam oxCore berfungsi sebagai satu-satunya sumber kebenaran yang menyatukan pandangan AAA, OLT, dan bisnis ke dalam satu entitas `Service` yang memiliki `desired_state`, `actual_state`, dan `status` workflow secara bersamaan. Modul Reconciliation yang berjalan sebagai scheduler periodik secara aktif membandingkan desired state dari inventory dengan actual state dari oxRADIUS dan oxOLT, mendeteksi mismatch, dan melakukan auto-heal atau eskalasi alert kepada operator sesuai kebijakan yang dikonfigurasi. Seluruh perubahan state dicatat dalam audit log append-only yang mendukung kepatuhan regulasi termasuk pemenuhan hak subjek data sesuai ketentuan GDPR.

Oxion mendukung deployment skala enterprise melalui Kubernetes dengan Helm chart dan ArgoCD GitOps, di mana komponen oxRADIUS di-deploy sebagai DaemonSet pada node akses untuk memastikan kedekatan jaringan dengan perangkat NAS, sementara oxCore dan oxBill di-deploy sebagai Deployment dengan Horizontal Pod Autoscaler yang mampu melakukan penskalaan dari dua hingga sepuluh replika berdasarkan beban CPU maupun metrik latensi autentikasi. Database layer menggunakan PostgreSQL 18 dengan ekstensi TimescaleDB untuk data time-series trafik dan akuntansi, Nebulex untuk caching in-process dan terdistribusi berbasis BEAM clustering, dan NATS JetStream sebagai event bus yang menghubungkan seluruh modul secara asinkron. Untuk kebutuhan multi-tenant dan white-label, setiap tenant mendapatkan isolasi penuh pada level data, konfigurasi branding, custom domain melalui CNAME, serta feature flag yang dapat dikustomisasi per tenant. ZITADEL digunakan sebagai identity provider terpusat yang mendukung OAuth2, OIDC, dan SAML 2.0 untuk integrasi SSO dengan sistem existing operator maupun mitra.

Dampak operasional dari implementasi Oxion dapat diukur secara konkret dari pengurangan jumlah sentuhan manual pada setiap siklus layanan. Sebelum Oxion, satu proses aktivasi atau suspensi layanan membutuhkan koordinasi minimal tiga orang dari tiga domain sistem yang berbeda — tim billing di ERP, operator AAA di panel RADIUS, dan teknisi jaringan di sistem OLT — dengan total waktu penyelesaian yang bergantung pada ketersediaan dan koordinasi antar tim. Dengan Oxion, happy path dari penerimaan pembayaran hingga layanan aktif sepenuhnya dieksekusi oleh sistem tanpa intervensi manusia, sementara operator teknis hanya dilibatkan pada kasus exception yang memerlukan penanganan manual. Berdasarkan estimasi konservatif, implementasi Oxion secara penuh berpotensi mengurangi sentuhan manual operasional sebesar 50 hingga 70 persen pada alur normal, mempercepat rata-rata waktu aktivasi layanan dari hitungan jam menjadi hitungan menit, serta menurunkan insiden inkonsistensi state antara sistem AAA dan OLT secara signifikan melalui mekanisme reconciliation yang berjalan otomatis.

---

## 4. Arsitektur Platform

```
Odoo / ERP / Portal
        ↓ intent bisnis
   ┌────────────────────────────────────┐
   │           oxCore                   │
   │  Orchestrator + Service Inventory  │
   │  Reconciliation + Workflow Engine  │
   └────┬──────────────┬────────────────┘
        ↓              ↓
  ┌─────────┐    ┌───────────┐
  │oxRADIUS │    │  oxOLT    │
  │AAA/RADIUS│   │OLT/Fiber  │
  └─────────┘    └───────────┘
        ↓              ↓
  FreeRADIUS     OLT Devices
  (MikroTik,     (Huawei, ZTE,
   Cisco, dll)    DOCSIS CMTS)

        ↑ metrics + events
   ┌─────────┐    ┌───────────┐
   │ oxNOC   │    │  oxBill   │
   │Monitoring│   │Billing+Pay│
   └─────────┘    └───────────┘
```

---

## 5. Domain

- **Utama:** `oxion.io` / `oxion.dev`
- **Produk:** `radius.oxion.io`, `olt.oxion.io`, `core.oxion.io`
- **Docs:** `docs.oxion.io`
