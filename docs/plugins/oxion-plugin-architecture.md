# Oxion Plugin Architecture

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](../architecture/oxion-infra-deployment-spec.md)
- [Platform Services Specification](../architecture/oxion-platform-services-spec.md)
- [oxCore Spec](../modules/oxcore-spec.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)
- [Oxion Docs Map](../README.md)
- [Plugin Examples](oxion-plugin-examples.md)

---

## 2. Tujuan

Plugin architecture Oxion dirancang agar setiap perusahaan dapat mengubah alur bisnis tanpa fork codebase utama.

Target utama:

- Satu core platform untuk semua tenant.
- Custom flow per perusahaan/tenant lewat plugin.
- Upgrade core tetap aman tanpa memutus plugin tenant.

---

## 3. Prinsip Desain

- **Simple by default:** Lite Mode tetap ringan tanpa plugin kompleks.
- **Powerful by choice:** plugin aktif hanya bila dibutuhkan.
- **Tenant-scoped:** plugin dapat aktif per tenant/per reseller.
- **Backward-compatible:** kontrak plugin versioned.
- **Safe execution:** sandbox + permission allowlist + audit trail.

---

## 4. Extension Surfaces

### 4.1 Flow Plugin (oxCore)

Hook utama:

- `before_step`
- `after_step`
- `on_error`
- `on_compensate`

Contoh use case:

- Alur aktivasi layanan dengan approval bertingkat.
- Penambahan validasi SLA kontrak enterprise sebelum provisioning.

### 4.2 Policy Plugin (oxRADIUS)

Hook utama:

- `pre_authorize`
- `post_authorize`
- `accounting_transform`

Contoh use case:

- Penyesuaian policy FUP spesifik regional.
- Rule anti-fraud custom per ISP.

### 4.3 Billing Plugin (oxBill)

Hook utama:

- `invoice_enrich`
- `payment_route`
- `commission_rule`

Contoh use case:

- Rumus komisi reseller bertingkat yang berbeda tiap perusahaan.
- Routing payment berdasar wilayah atau channel preferensi.

### 4.4 UI Plugin

Hook utama:

- `menu_extend`
- `dashboard_widget`
- `custom_page`

Contoh use case:

- Widget KPI internal perusahaan.
- Halaman operasional khusus tim NOC/billing setempat.

### 4.5 Integration Plugin

Hook utama:

- `outbound_event_handler`
- `inbound_webhook_adapter`

Contoh use case:

- Integrasi ERP/CRM lokal.
- Adapter WhatsApp gateway on-prem.

---

## 5. Manifest & Kontrak Plugin

### 5.1 Plugin Manifest

```json
{
  "id": "com.oxion.plugin.custom-approval",
  "name": "Custom Approval Flow",
  "version": "1.2.0",
  "api_version": "v1",
  "runtime": {
    "language": "typescript",
    "version": "5.x"
  },
  "type": "flow",
  "entrypoint": "main",
  "hooks": ["before_step", "after_step", "on_error"],
  "permissions": ["read:service", "write:workflow", "emit:event"],
  "tenant_scope": "tenant",
  "config_schema": {
    "type": "object",
    "properties": {
      "max_auto_approve": { "type": "number" }
    }
  }
}
```

### 5.2 Hook Contract (Flow)

```json
{
  "hook": "before_step",
  "tenant_id": "tnt_123",
  "workflow": {
    "job_id": "job_001",
    "step": "activate_radius",
    "payload": {}
  },
  "context": {
    "actor_id": "usr_001",
    "request_id": "req_abc"
  }
}
```

Expected response:

```json
{
  "decision": "allow",
  "patch": {},
  "reason": "policy_matched"
}
```

---

## 6. Runtime & Isolasi Eksekusi

Model runtime v1:

- Plugin dieksekusi melalui **Plugin Runner Service** terpisah.
- Komunikasi dengan core menggunakan event/request contract terstandar.
- Eksekusi dibatasi timeout, memory quota, dan concurrency quota.

Bahasa plugin yang didukung untuk v1 (dibatasi dulu agar operasional stabil):

- **TypeScript** (Node.js runtime)
- **Python**
- **Elixir**

Di luar tiga bahasa ini belum didukung pada v1.

Guardrails wajib:

- Per-plugin permission allowlist.
- Network egress allowlist.
- Tidak ada akses DB langsung tanpa gateway API.
- Semua eksekusi plugin dicatat ke `audit_log`.

---

## 7. Lifecycle Plugin

Tahapan:

1. `upload`
2. `verify-signature`
3. `compat-check` (api version)
4. `staging-enable`
5. `production-enable`
6. `rollback` (jika issue)

State plugin:

- `draft`
- `verified`
- `enabled_staging`
- `enabled_production`
- `disabled`

---

## 8. Multi-Tenant Activation Model

Activation level:

- global (sangat terbatas, hanya internal)
- tenant
- reseller

Resolusi konfigurasi:

`global default -> tenant override -> reseller override`

---

## 9. API Management Plugin (Draft)

```http
POST   /v1/plugins/upload
POST   /v1/plugins/:id/verify
POST   /v1/plugins/:id/enable?scope=tenant&tenant_id={id}
POST   /v1/plugins/:id/disable?scope=tenant&tenant_id={id}
POST   /v1/plugins/:id/rollback
GET    /v1/plugins
GET    /v1/plugins/:id/executions
```

---

## 10. Deployment Model

- **Lite Mode:** plugin runner optional; default nonaktif agar footprint kecil.
- **Platform Mode:** plugin runner aktif, dipantau via oxNOC, autoscaling sesuai throughput.

---

## 11. Roadmap Implementasi Plugin v1

- [ ] Definisi kontrak `api_version=v1` untuk flow/policy/billing plugin.
- [ ] Runtime matrix v1: TypeScript, Python, Elixir.
- [ ] Plugin manifest validator + signature verification.
- [ ] Plugin runner service + timeout/quota enforcement.
- [ ] Tenant-scoped plugin activation.
- [ ] UI plugin management (upload, enable, rollback).
- [ ] Observability plugin execution (latency/error/success metrics).

---

## 12. Non-Goals v1

- Marketplace publik plugin.
- Hot reload tanpa verifikasi.
- Akses langsung plugin ke database inti.

---

## 13. Contoh Implementasi

Contoh konkret manifest + hook plugin dengan komentar tersedia di:

- `oxion-plugin-examples.md`
- `plugin-manifest.schema.json`
- `plugin-starter/README.md`
