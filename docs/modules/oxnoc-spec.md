# oxNOC — Monitoring & Dashboard

**Bagian dari platform:** Oxion ISP Operating Platform
**Versi:** 2.0
**Stack:** Prometheus + Grafana + Loki + Tempo + SolidJS

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](../architecture/oxion-infra-deployment-spec.md)
- [Platform Overview](../architecture/oxion-platform-overview.md)
- [Platform Services Specification](../architecture/oxion-platform-services-spec.md)
- [oxCore Spec](oxcore-spec.md)
- [oxRADIUS Spec](oxradius-spec.md)
- [oxOLT Spec](oxolt-spec.md)
- [oxBill Spec](oxbill-spec.md)
- [Brand Naming](../architecture/oxion-brand-naming.md)

---

## 2. Ringkasan

oxNOC adalah modul observabilitas dan monitoring terpusat dari platform Oxion. Mengumpulkan metrik dari seluruh komponen (oxRADIUS, oxOLT, oxCore, oxBill), menyajikan dashboard real-time, dan mengelola alert operasional kepada tim NOC.

---

## 3. Arsitektur Observabilitas

```
oxRADIUS  oxOLT  oxCore  oxBill
    ↓ metrics (Prometheus scrape)
Prometheus
    ↓
Grafana Dashboards
    ↓ alerts
Alertmanager → oxNOC Alert Engine
    ↓ notify
WhatsApp / Telegram / Email / PagerDuty

oxRADIUS  oxOLT  oxCore  oxBill
    ↓ logs (structured JSON)
Loki (log aggregation)
    ↓
Grafana (log explorer + correlation)

oxRADIUS  oxOLT  oxCore
    ↓ traces (OpenTelemetry)
Tempo (distributed tracing)
    ↓
Grafana (trace explorer)
```

---

## 4. Modul

### dashboard
- Endpoint dan agregasi data ringkasan
- `_service` — komputasi metrik/status

### activity-log
- Pencatatan aktivitas operasional user/perangkat
- `services` — query, filter, transform log

### graph
- Data graf/visualisasi untuk analitik
- Dipakai oleh komponen chart di UI

### notification (alert)
- Distribusi alert ke channel operator
- Integrasi dengan notification_engine oxRADIUS

### snmp (monitoring)
- Polling signal optik ONU secara periodik
- Monitoring temperatur OLT
- Worker queue untuk SNMP jobs

---

## 5. Dashboard Grafana

### Dashboard: Oxion Overview

```
Row: AAA Real-time
├── Active Sessions (gauge)
├── Auth/s (time series)
├── Deny Rate % (time series)
└── Auth Latency p50/p95/p99 (time series)

Row: Service Health
├── Services Active (stat)
├── Services Inconsistent (stat — merah jika > 0)
├── Reconciliation Last Run (time)
└── Pending Workflow Jobs (gauge)

Row: OLT & Fiber
├── OLT Online/Offline (table)
├── ONU Total per Status (stacked bar)
├── Signal Level per OLT (heatmap)
└── Provision Success Rate (gauge)

Row: Business
├── Revenue Today (stat)
├── Active Subscribers (stat)
├── Vouchers Redeemed Today (stat)
└── Failed Payments (stat)

Row: BEAM VM (oxRADIUS)
├── Process Count (gauge)
├── Memory Usage (area)
└── Scheduler Utilization (multi-line)
```

### Dashboard: ONU Signal Detail

```
├── Rx Power Distribution (histogram)
├── Tx Power Over Time (time series per ONU)
├── SNR Trend (time series)
├── ONU Offline Events (event markers)
└── LOS/LOSi Alert History (table)
```

### Dashboard: Workflow Monitor

```
├── Jobs per Type per Hour (bar chart)
├── Job Success Rate (gauge)
├── Failed Steps (table — drilldown ke trace)
├── Average Activation Time (trend)
└── Reconciliation Mismatch Count (time series)
```

---

## 6. Prometheus Metrics Lengkap

### oxRADIUS

```
# Auth
aaa_authorize_total{tenant_id, result}
aaa_authorize_duration_ms{quantile="0.5|0.95|0.99"}
aaa_accounting_total{tenant_id, type}
aaa_active_sessions_total{tenant_id, nas_id}

# Quota & FUP
aaa_quota_exhausted_total{tenant_id}
aaa_fup_activated_total{tenant_id}
aaa_quota_usage_bytes{subscriber_id}

# Fraud
aaa_anomaly_detected_total{tenant_id, action}
aaa_fraud_score_histogram_bucket{tenant_id, le}

# CoA
aaa_coa_sent_total{tenant_id, result}
aaa_pod_sent_total{tenant_id, result}
```

### oxOLT

```
oxolt_onu_total{tenant_id, status}
oxolt_onu_rx_power_dbm{olt_id, onu_id}
oxolt_onu_tx_power_dbm{olt_id, onu_id}
oxolt_onu_snr_db{olt_id, onu_id}
oxolt_provision_success_total{vendor}
oxolt_provision_fail_total{vendor}
oxolt_nas_online_total{tenant_id}
oxolt_nas_offline_total{tenant_id}
oxolt_firmware_upgrade_total{vendor, status}
oxolt_snmp_poll_duration_ms{olt_id}
```

### oxCore

```
oxcore_service_total{status}
oxcore_service_inconsistent_total{tenant_id}
oxcore_workflow_job_total{job_type, status}
oxcore_workflow_step_duration_ms{step_name}
oxcore_reconciliation_mismatch_total{type}
oxcore_reconciliation_duration_ms
oxcore_activation_duration_ms{quantile}
```

### oxBill

```
oxbill_invoice_total{tenant_id, status}
oxbill_payment_total{tenant_id, method, status}
oxbill_revenue_total{tenant_id, currency}
oxbill_voucher_generated_total{tenant_id}
oxbill_voucher_redeemed_total{tenant_id}
oxbill_voucher_expired_total{tenant_id}
```

---

## 7. Alert Rules

### Kritis (P1 — immediate)

```yaml
# Auth latency terlalu tinggi
- alert: AAAHighLatency
  expr: aaa_authorize_duration_ms{quantile="0.99"} > 100
  for: 2m

# OLT offline
- alert: OLTOffline
  expr: oxolt_nas_online_total == 0
  for: 1m

# Banyak service inconsistent
- alert: ManyInconsistentServices
  expr: oxcore_service_inconsistent_total > 10
  for: 5m

# Auth deny rate tinggi
- alert: HighDenyRate
  expr: rate(aaa_authorize_total{result="deny"}[5m]) / rate(aaa_authorize_total[5m]) > 0.3
  for: 3m
```

### Warning (P2)

```yaml
# Signal ONU lemah
- alert: WeakONUSignal
  expr: oxolt_onu_rx_power_dbm < -27
  for: 5m

# Workflow job stuck
- alert: WorkflowJobStuck
  expr: time() - oxcore_workflow_job_start_time > 600
  for: 1m

# Voucher hampir habis
- alert: LowVoucherStock
  expr: oxbill_voucher_available_total < 10
```

---

## 8. Activity Log

Semua aktivitas operator dicatat:

```typescript
interface ActivityLog {
  id: string
  tenant_id: string
  actor_id: string
  actor_role: string
  action: string
  resource_type: string   // 'service' | 'onu' | 'subscriber' | 'invoice'
  resource_ref?: string
  subject_ref?: string
  subject_alias?: string
  change_summary: object
  privacy_class: string
  retention_class: string
  legal_basis: string
  timestamp: Date
  success: boolean
  error_code?: string
}
```

`oxNOC` hanya menampilkan audit utama yang sudah redacted. Raw `ip_address`, `user_agent`, dan private support context tidak boleh ikut menjadi default activity feed.

---

## 9. Loki Log Queries

### Auth failures per tenant
```logql
{service="oxradius"} | json | result="deny" | stats count() by (tenant_id)
```

### OLT provision failures
```logql
{service="oxolt"} | json | level="error" | step_name="olt_provision"
```

### Slow workflow steps
```logql
{service="oxcore"} | json | duration_ms > 5000 | line_format "{{.step_name}}: {{.duration_ms}}ms"
```

---

## 10. Tempo Distributed Tracing

Setiap request di-trace end-to-end:

```
HTTP Request (operator)
  └── oxCore.activateService
        ├── oxCore.validateService
        ├── AAAAdapter.enableUser
        │     └── oxRADIUS.updateSubscriber
        │           └── PostgreSQL.update
        ├── OLTAdapter.provision
        │     └── oxOLT.provisionONU
        │           ├── SNMP.getOLT
        │           └── Telnet.sendCommand
        └── oxCore.reconcileService
```

---

## 11. Real-time WebSocket Events

```typescript
// Topics yang bisa di-subscribe oleh UI
'sessions.updated'       // live session changes
'onu.status_changed'     // ONU online/offline
'service.state_changed'  // service status update
'workflow.step_completed'// workflow progress
'alert.triggered'        // new alert
'anomaly.detected'       // AI fraud detection
```

---

## 12. UI Operator (oxNOC Dashboard)

### Halaman utama
- Stats bar: total sessions, inconsistent services, OLT status, revenue hari ini
- Live session table (WebSocket)
- Recent alerts
- Workflow queue status

### Halaman Service Detail
- Summary (customer, paket, 3 dimensi state)
- AAA panel (username, enabled, last auth, tombol disconnect)
- OLT panel (OLT, FSP, ONU serial, VLAN, provision status, Rx power)
- Workflow panel (current job, step-by-step, retry button, reconcile now)
- Activity log

### Halaman GIS Map
- Marker OLT (hijau = online, merah = offline)
- Popup: nama OLT, jumlah ONU, sessions aktif
- Coverage polygon

---

## 13. Report & Export

```
GET /v1/reports/overview
GET /v1/reports/traffic/subscriber/:id
GET /v1/reports/top-users
GET /v1/reports/nas-utilization
GET /v1/reports/signal/:nas_id
GET /v1/reports/workflow-summary
GET /v1/reports/export?format=csv|xlsx
```

---

## 14. Notification Engine

Channel yang didukung:
- **WhatsApp** (Meta Business API / Fonnte)
- **Telegram** (Bot API)
- **Email** (SMTP / Postmark)
- **SMS** (Twilio / Vonage)
- **Push** (FCM / APNs)

### Event Types

```
service.activated
service.suspended
service.terminated
service.inconsistent_detected
onu.offline
olt.offline
workflow.failed
alert.p1_triggered
quota.warning (80%)
quota.exhausted
fraud.detected
```
