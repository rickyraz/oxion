# oxCore — Orchestrator & Service Inventory

**Bagian dari platform:** Oxion ISP Operating Platform
**Versi:** 2.0
**Stack:** TypeScript/Node.js + PostgreSQL

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](../architecture/oxion-infra-deployment-spec.md)
- [Platform Overview](../architecture/oxion-platform-overview.md)
- [Platform Services Specification](../architecture/oxion-platform-services-spec.md)
- [oxRADIUS Spec](oxradius-spec.md)
- [oxOLT Spec](oxolt-spec.md)
- [oxBill Spec](oxbill-spec.md)
- [oxNOC Spec](oxnoc-spec.md)
- [Brand Naming](../architecture/oxion-brand-naming.md)
- [Plugin Architecture](../plugins/oxion-plugin-architecture.md)

---

## 2. Ringkasan

oxCore adalah otak dari platform Oxion. Berperan sebagai single control plane yang menerima intent bisnis dari ERP (Odoo), menyimpan source of truth layanan, mengatur eksekusi ke oxRADIUS dan oxOLT, serta memastikan seluruh sistem selalu sinkron melalui Reconciliation.

**Prinsip utama:**
> Odoo kirim intent → oxCore memutuskan → oxRADIUS + oxOLT mengeksekusi

---

## 3. Arsitektur

```
Odoo / ERP / Operator Portal
        ↓ intent (activate/suspend/terminate)
┌─────────────────────────────────────────────┐
│                  oxCore                      │
│                                              │
│  ┌─────────────┐   ┌────────────────────┐   │
│  │ Orchestrator │   │ Service Inventory  │   │
│  │  (commands)  │   │  (source of truth) │   │
│  └──────┬───────┘   └────────────────────┘   │
│         ↓                                    │
│  ┌─────────────┐   ┌────────────────────┐   │
│  │ AAA Adapter  │   │   OLT Adapter      │   │
│  └──────┬───────┘   └────────┬───────────┘   │
│         ↓                    ↓               │
│  ┌─────────────────────────────────────────┐ │
│  │           Reconciliation                 │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
        ↓               ↓
   oxRADIUS          oxOLT
```

---

## 4. Modul

```
src/modules
  /service            ← Service Inventory
    /_service
    /types
    /repository

  /orchestrator       ← Orchestrator
    /commands
    /planner
    /executor
    /_service

  /reconciliation     ← Reconciliation engine
    /_service
    /scheduler
    /rules

  /aaa-adapter        ← Façade ke oxRADIUS
    /_service
    /providers

  /olt-adapter        ← Façade ke oxOLT
    /_service
    /providers
```

---

## 5. Domain Model

### Service (entitas paling penting)

```sql
CREATE TABLE services (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id             UUID NOT NULL REFERENCES customers(id),
  package_id              UUID NOT NULL REFERENCES packages(id),
  external_odoo_order_id  TEXT,
  service_number          TEXT UNIQUE NOT NULL,

  -- Workflow execution state
  status         TEXT NOT NULL,
  -- draft | pending_activation | active | throttled_due_overdue
  -- suspended | terminating | terminated | inconsistent

  desired_state  TEXT NOT NULL,
  -- active | suspended | terminated

  operational_state TEXT NOT NULL DEFAULT 'normal',
  -- normal | throttled_due_overdue | suspended_due_overdue

  actual_state   TEXT NOT NULL DEFAULT 'unknown',
  -- active | suspended | terminated | partial | unknown

  activation_date   TIMESTAMPTZ,
  suspension_reason TEXT,
  termination_reason TEXT,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

### Customers

```sql
CREATE TABLE customers (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_odoo_id TEXT UNIQUE,
  full_name        TEXT NOT NULL,
  phone            TEXT,
  email            TEXT,
  status           TEXT DEFAULT 'active',
  created_at       TIMESTAMPTZ DEFAULT now()
);
```

### Packages

```sql
CREATE TABLE packages (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 TEXT UNIQUE NOT NULL,
  name                 TEXT NOT NULL,
  bandwidth_down_kbps  INTEGER,
  bandwidth_up_kbps    INTEGER,
  radius_profile       TEXT,
  olt_service_profile  TEXT,
  olt_line_profile     TEXT,
  fup_policy           JSONB,
  is_active            BOOLEAN DEFAULT true
);
```

### WorkflowJob

```sql
CREATE TABLE workflow_jobs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id  UUID REFERENCES services(id),
  job_type    TEXT NOT NULL,
  -- activate_service | suspend_service | terminate_service
  -- change_package | reconcile_service

  status      TEXT NOT NULL,
  -- pending | running | success | failed | partial

  requested_by TEXT,
  source       TEXT NOT NULL,
  -- odoo | operator | scheduler | system

  payload      JSONB DEFAULT '{}',
  error_message TEXT,
  retry_count  INTEGER DEFAULT 0,
  started_at   TIMESTAMPTZ,
  finished_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT now()
);
```

### WorkflowSteps

```sql
CREATE TABLE workflow_steps (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id      UUID NOT NULL REFERENCES workflow_jobs(id),
  step_order  INTEGER NOT NULL,
  step_name   TEXT NOT NULL,
  -- aaa_enable | aaa_disable | aaa_disconnect
  -- olt_provision | olt_deprovision
  -- reconcile_aaa | reconcile_olt

  status      TEXT NOT NULL,
  -- pending | running | success | failed | skipped

  payload     JSONB DEFAULT '{}',
  result      JSONB,
  error_message TEXT,
  started_at  TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);
```

### ServiceStateSnapshots (untuk reconciliation)

```sql
CREATE TABLE service_state_snapshots (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id   UUID NOT NULL REFERENCES services(id),
  source       TEXT NOT NULL,
  -- inventory | aaa | olt

  state        JSONB NOT NULL,
  collected_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 6. Orchestrator Commands

### ActivateService

```
Steps:
1. validate_service
2. ensure_inventory_complete
3. aaa_enable
4. olt_provision
5. aaa_disconnect_optional   (force reconnect dengan setting baru)
6. reconcile_service
7. mark_service_active
```

### SuspendService

```
Steps:
1. validate_service
2. aaa_disable_or_quarantine
3. aaa_disconnect
4. olt_apply_isolation_optional
5. reconcile_service
6. mark_service_suspended
```

### TerminateService

```
Steps:
1. validate_service
2. aaa_disable
3. aaa_disconnect
4. olt_deprovision
5. release_attachment
6. reconcile_service
7. mark_service_terminated
```

### ChangePackage

```
Steps:
1. validate_new_package
2. detect_profile_diff     (idempotency guard: skip jika profile sama)
3. aaa_update_profile
4. aaa_send_coa_if_needed  (jangan kirim CoA berulang jika profile sudah aktif)
5. olt_change_profile_optional
6. reconcile_service
7. mark_package_updated
```

---

## 7. State Machine

```
Transitions:
draft              → pending_activation
pending_activation → active
active             → throttled_due_overdue
throttled_due_overdue → active
throttled_due_overdue → suspended
active             → suspended
suspended          → active
active             → terminating
suspended          → terminating
terminating        → terminated
any                → inconsistent
```

### Operational State (Collection-Aware)

Selain `desired_state` dan `status`, Oxion memakai `operational_state` untuk kondisi enforcement non-terminal.

Nilai utama:

- `normal`
- `throttled_due_overdue`
- `suspended_due_overdue`

Dengan pendekatan ini, layanan bisa tetap `desired_state=active` sambil berada di mode throttled karena tunggakan.

### Empat Dimensi State

| Field | Arti |
|---|---|
| `desired_state` | Target yang diinginkan bisnis |
| `operational_state` | Mode operasional non-terminal (mis. throttle overdue) |
| `status` | Posisi dalam workflow eksekusi |
| `actual_state` | Hasil nyata di lapangan (AAA + OLT) |

---

## 8. Reconciliation Engine

### Aturan

| Desired State | AAA | OLT |
|---|---|---|
| `active` | harus enabled | harus provisioned |
| `suspended` | harus disabled | boleh provisioned atau isolated |
| `terminated` | harus disabled | harus removed |

### Output Reconciliation

- Update `actual_state` di tabel `services`
- Buat alert di oxNOC jika mismatch
- Buat `reconcile_service` job jika auto-heal aktif
- Simpan snapshot ke `service_state_snapshots`

### Jadwal

```
Setiap 5 menit  → reconcile services dengan status 'inconsistent'
Setiap 1 jam    → full reconciliation semua active services
Setiap 6 jam    → deep scan termasuk OLT signal + AAA accounting
```

---

## 9. AAA Adapter Interface

```typescript
interface AaaAdapter {
  enable_user(service_id: string): Promise<Result>
  disable_user(service_id: string): Promise<Result>
  disconnect_user(service_id: string): Promise<Result>
  update_profile(service_id: string, profile: AaaProfile): Promise<Result>
  send_coa(service_id: string, attributes: RadiusAttr[]): Promise<Result>
  fetch_state(service_id: string): Promise<AaaState>
}
```

## 10. OLT Adapter Interface

```typescript
interface OltAdapter {
  provision(service_id: string): Promise<Result>
  deprovision(service_id: string): Promise<Result>
  change_package(service_id: string, package_id: string): Promise<Result>
  replace_onu(service_id: string, new_serial: string): Promise<Result>
  fetch_state(service_id: string): Promise<OltState>
}
```

---

## 11. Event Flow

### Payment Received (dari Odoo)

```
Odoo → POST /v1/events/payment-received
  { service_id, amount, invoice_id }

oxCore:
  1. set desired_state = 'active'
  2. create ActivateService job
  3. execute steps
  4. emit service.activated event
  5. notify via oxNOC
```

### Invoice Overdue (dari Odoo)

```
Odoo → POST /v1/events/invoice-overdue
  { service_id, invoice_id, days_overdue }

oxCore:
  1. load collection policy tenant
  2. evaluate stage rules (condition AST + priority)
  3. run stage actions:
       - apply_bandwidth_profile -> ChangePackage
       - suspend_service -> SuspendService
       - send_notification -> notification_engine
       - emit_event -> NATS JetStream
  4. map operational_state berdasarkan action outcome
       - throttle action -> 'throttled_due_overdue'
       - suspend action  -> 'suspended_due_overdue'
  5. enforce idempotency via action fingerprint
```

### Payment Received (restore from overdue)

```text
Jika service ada pada throttled/suspended karena overdue:
  1. set operational_state = 'normal'
  2. restore package/profile asli subscriber
  3. unsuspend jika sebelumnya suspended_due_overdue
  4. emit service.restored event
```

### Terminate Request

```
Odoo → POST /v1/events/terminate-request
  { service_id, reason }

oxCore:
  1. set desired_state = 'terminated'
  2. create TerminateService job
  3. execute steps
  4. emit service.terminated event
```

---

## 12. API Endpoints

### Commands

```
POST /v1/services/:id/activate
POST /v1/services/:id/suspend
POST /v1/services/:id/terminate
POST /v1/services/:id/reconcile
POST /v1/services/:id/change-package
POST /v1/services/:id/replace-onu
```

### Read

```
GET  /v1/services
GET  /v1/services/:id
GET  /v1/services/:id/state
GET  /v1/services/:id/workflows
GET  /v1/services/:id/workflows/:job_id/steps
GET  /v1/services?status=inconsistent
GET  /v1/services?desired_state=active&actual_state=unknown

GET  /v1/customers
GET  /v1/customers/:id
GET  /v1/customers/:id/services

GET  /v1/packages
POST /v1/packages
PUT  /v1/packages/:id
```

### Odoo Webhooks

```
POST /v1/webhooks/odoo/payment-received
POST /v1/webhooks/odoo/invoice-overdue
POST /v1/webhooks/odoo/terminate-request
POST /v1/webhooks/odoo/service-created
POST /v1/webhooks/odoo/package-changed
```

---

## 13. Service Inventory View (untuk UI Operator)

```json
{
  "service_id": "svc_123",
  "service_number": "SVC-2025-001234",
  "customer": {
    "name": "PT Maju Bersama",
    "phone": "+6281234567890"
  },
  "package": {
    "name": "50 Mbps Business",
    "download_kbps": 51200,
    "upload_kbps": 25600
  },
  "desired_state": "active",
  "actual_state": "partial",
  "status": "inconsistent",
  "aaa": {
    "username": "ptmaju001",
    "enabled": true,
    "last_auth_at": "2025-03-19T10:30:00Z",
    "active_session": true
  },
  "network": {
    "olt": "OLT-JKT-01",
    "fsp": "0/1/3",
    "onu_id": 12,
    "onu_serial": "48575443ABCD1234",
    "vlan": 1203,
    "provision_status": "failed",
    "rx_power_dbm": -18.5
  },
  "last_workflow": {
    "job_type": "activate_service",
    "status": "partial",
    "failed_step": "olt_provision",
    "error": "OLT unreachable"
  }
}
```

---

## 14. Prinsip Implementasi

1. **Semua step idempotent** — aman dipanggil lebih dari sekali
2. **Tidak ada UI yang langsung ke oxRADIUS/oxOLT** — semua lewat oxCore
3. **Source of truth** tetap di Service Inventory — bukan di FreeRADIUS, bukan di OLT
4. **Adapter hanya executor** — semua keputusan di Orchestrator
5. **Workflow sebagai audit trail** — setiap langkah tercatat

---

## 15. Dampak Operasional

| Metrik | Sebelum | Sesudah |
|---|---|---|
| Orang per aktivasi | 3 orang | 1 orang (happy path) |
| Orang per suspensi | 3 orang | 0 orang (otomatis) |
| Waktu aktivasi | 30–120 menit | 1–3 menit |
| Insiden mismatch AAA↔OLT | Tinggi | Sangat rendah (auto-reconcile) |
| Audit trail | Manual/tidak ada | Lengkap otomatis |
