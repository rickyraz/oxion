# Oxion Platform Purpose and System Thesis

## 1. Dokumen Terkait

- [Platform Overview](oxion-platform-overview.md)
- [Master Arsitektur & Deployment](oxion-infra-deployment-spec.md)
- [Platform Services Specification](oxion-platform-services-spec.md)
- [Brand Identity](oxion-brand-naming.md)
- [oxCore Spec](../modules/oxcore-spec.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)
- [oxOLT Spec](../modules/oxolt-spec.md)
- [oxNOC Spec](../modules/oxnoc-spec.md)
- [oxBill Spec](../modules/oxbill-spec.md)

---

## 2. Tujuan Dokumen

Dokumen ini merangkum tujuan strategis Oxion sebagai platform, bukan sekadar kumpulan modul teknis.
Fokus utamanya adalah positioning, arsitektur kendali, dan alasan kenapa Oxion dibangun sebagai system layer baru untuk operasi ISP.

---

## 3. Final Positioning

**Oxion** adalah:

> **ISP Operating Platform**

Posisi ini menegaskan bahwa Oxion bukan dashboard, bukan AAA tool tunggal, dan bukan OLT manager terpisah.
Oxion adalah platform operasi terpadu yang mengendalikan lifecycle layanan ISP end-to-end.

Alternative framing yang tetap konsisten:

- `Operating Platform for ISPs`
- `Operating System for ISP Infrastructure`

Default positioning yang direkomendasikan untuk komunikasi produk tetap: **ISP Operating Platform**.

---

## 4. Core Thesis

Masalah utama industri bukan ketiadaan fitur, tetapi fragmentasi control plane.
Banyak stack ISP memiliki komponen kuat secara individual (AAA, OLT, billing), tetapi tidak memiliki satu sistem yang memegang intent, state, dan eksekusi secara terpadu.

Thesis Oxion:

1. Satukan intent bisnis dan eksekusi jaringan dalam satu control plane.
2. Pisahkan dengan tegas `intent`, `desired state`, dan `execution`.
3. Jadikan operasi bersifat automated, auditable, dan resilient.
4. Kurangi peran operator sebagai manual glue; operator fokus pada intent dan exception handling.

---

## 5. Product System

```text
Oxion Platform

  oxCore   -> control plane (orchestrator + service inventory)
  oxRADIUS -> AAA + policy execution
  oxOLT    -> fiber and OLT execution
  oxNOC    -> monitoring and observability
  oxBill   -> billing and payment
```

Insight pembeda:

- Banyak vendor punya AAA, OLT, dan billing.
- Sedikit yang punya **unified control plane**.
- Nilai utama Oxion ada pada orkestrasi lintas domain, bukan pada satu modul terisolasi.

---

## 6. Peran Setiap Modul

### oxCore (jantung platform)

- orchestrator
- service inventory
- workflow engine
- single source of truth

### oxRADIUS

- policy engine
- FreeRADIUS integration
- auth + accounting execution

### oxOLT

- ONU lifecycle
- VLAN/profile enforcement
- remote command and provisioning execution

### oxNOC

- dashboard operasional
- alerting and anomaly visibility
- SLA and operational health view

### oxBill

- billing lifecycle
- payment gateway integration
- invoicing and subscription logic

---

## 7. Architecture Statement

Gunakan pernyataan berikut untuk website, deck, dan dokumentasi arsitektur:

```text
Oxion is an ISP Operating Platform that provides a unified control plane
to orchestrate subscriber lifecycle across AAA, network infrastructure,
and business systems.

It separates intent, desired state, and execution, enabling automated,
auditable, and resilient ISP operations at scale.
```

---

## 8. Historical Mapping (Unix GNU Linux Analogy)

Analogi ini dipakai sebagai alat berpikir arsitektur, bukan klaim kesetaraan historis.

### Sebelum Oxion (fragmented ISP stack)

```text
Network devices (OLT, NAS)
  -> vendor tools and AAA stack
  -> ERP/panel
  -> human operator as glue
```

### Dengan Oxion (unified control plane)

```text
Network devices (OLT, NAS)
  -> execution layer (AAA and network modules)
  -> Oxion control plane (oxCore)
  -> business systems
  -> operator for intent and exception
```

Mapping konsep:

- Kernel pada OS <-> oxCore sebagai control plane.
- Syscall boundary <-> workflow step boundary.
- Userland tools <-> execution subsystems (`oxRADIUS`, `oxOLT`).
- Observability tooling <-> `oxNOC`.

Makna praktisnya:

- Oxion tidak harus mengganti semua komponen existing.
- Oxion mengganti **cara komponen dikendalikan**.

---

## 9. Strategic One-Liner

Kalimat ringkas untuk positioning eksternal:

> Oxion adalah control plane yang mengubah operasi ISP dari sistem manual terfragmentasi menjadi sistem terorkestrasi penuh.

Kalimat ringkas untuk framing historis:

> Seperti GNU/Linux mengganti kontrol komputasi tanpa mengganti hardware, Oxion mengganti kontrol operasi ISP tanpa harus mengganti seluruh AAA dan OLT stack yang sudah berjalan.

