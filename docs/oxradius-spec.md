# oxRADIUS — AAA & Policy Engine

**Bagian dari platform:** Oxion ISP Operating Platform
**Versi:** 2.0
**Stack:** Gleam + FreeRADIUS + BEAM VM

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](./oxion-infra-deployment-spec.md)
- [Platform Overview](./oxion-platform-overview.md)
- [Platform Services Specification](./oxion-platform-services-spec.md)
- [oxCore Spec](./oxcore-spec.md)
- [oxBill Spec](./oxbill-spec.md)
- [oxOLT Spec](./oxolt-spec.md)
- [oxNOC Spec](./oxnoc-spec.md)
- [Brand Naming](./oxion-brand-naming.md)
- [Plugin Architecture](./oxion-plugin-architecture.md)
- [dalo Migration Runbook](./oxion-dalo-migration-runbook.md)
- [Tier-1 Broadband Interop Profile](./oxion-tier1-broadband-interoperability-profile.md)
- [RADIUS Access-Accept and CoA Examples](./radius-access-coa-examples.md)
- [NAS Vendor Mapping Template](./nas-vendor-mapping-template.md)

---

## 2. Ringkasan

oxRADIUS adalah modul Authentication, Authorization, dan Accounting (AAA) dari platform Oxion. Dibangun di atas FreeRADIUS 3.2.x dengan lapisan logika kebijakan yang ditulis menggunakan bahasa Gleam di atas BEAM Virtual Machine. Berkomunikasi dengan FreeRADIUS melalui modul `rlm_rest` via HTTPS.

**Target performa:** ≥ 10.000 auth/s pada 2 node, p99 latency < 30ms.

### Profil Operasi

- **Lite Mode:** fokus panel operasional inti seperti daloRADIUS (subscriber, NAS, profile, session, accounting, voucher).
- **Platform Mode:** seluruh kapabilitas Oxion aktif (multi-tenant, orchestration, realtime, billing lanjutan, observability penuh).

Mode dijalankan di codebase yang sama, dikendalikan melalui profile config dan feature flags.

---

## 3. Arsitektur

```
NAS (MikroTik/Cisco/pfSense)
        ↓ RADIUS/UDP 1812/1813
FreeRADIUS Cluster (DaemonSet)
  rlm_rest → oxRADIUS Policy API
  rlm_eap  → EAP/PEAP/TLS
  CoA/PoD  ← CoA Dispatcher (UDP 3799)
        ↓
  radius_gateway  ←→  accounting_pipeline
        ↓
  policy_engine (Gleam, pure functional)
        ↓
  cache_layer (ETS + Nebulex)
        ↓
  PostgreSQL + NATS JetStream
```

---

## 4. Komponen Gleam OTP

### radius_gateway
Jembatan antara FreeRADIUS dan policy engine.
- `radius_gateway.gleam` — entry point
- `radius_packet.gleam` — parsing paket RADIUS
- `coa_dispatcher.gleam` — RFC 5176 CoA/PoD
- `realm_router.gleam` — routing berdasarkan realm

### policy_engine
Evaluator kebijakan AAA yang murni fungsional.
- `policy_engine.gleam` — `evaluate_policy/2` entry point
- `policy_types.gleam` — semua custom type
- `quota_checker.gleam` — quota + FUP
- `vlan_assigner.gleam` — assignment VLAN
- `time_policy.gleam` — time-based access
- `fraud_scorer.gleam` — anti-fraud scoring
- `device_fingerprint.gleam` — MAC + UA fingerprinting

### accounting_pipeline
Pemrosesan akuntansi asinkron.
- `accounting_pipeline.gleam`
- `session_tracker.gleam` — tracking sesi aktif via ETS
- `quota_updater.gleam` — update quota real-time
- `fup_evaluator.gleam` — penegakan FUP policy
- `traffic_aggregator.gleam` — rollup stats per periode
- `billing_emitter.gleam` — emit event ke oxBill

### cache_layer
- ETS in-process: TTL 30 detik
- Nebulex distributed cache: TTL 300 detik

---

## 5. Policy Types (Gleam)

```gleam
pub type PolicyResult {
  Allow(attributes: List(RadiusReplyAttribute))
  AllowWithFup(attributes: List(RadiusReplyAttribute), fup_reason: String)
  Deny(reason: DenyReason)
  DenyWithMessage(reason: DenyReason, reply_message: String)
  DenyFraudSuspected(score: Float, flags: List(AnomalyFlag))
}

pub type AnomalyFlag {
  MultipleSimultaneousSessions
  UnusualTrafficSpike
  BotLoginPattern
  GeoImpossibleTravel
  QuotaAbusePattern
}

pub type AuthMethod {
  PAP | CHAP | MSCHAP | MSCHAPv2
  EAPMD5 | EAPPEAP | EAPTLS
  MACAuth | VoucherAuth
}

pub type VsaAttribute {
  MikroTikRateLimit(download_kbps: Int, upload_kbps: Int)
  MikroTikAddressPool(pool_name: String)
  MikroTikGroup(group_name: String)
  CiscoAVPair(value: String)
  Generic(vendor_id: Int, attr_id: Int, value: String)
}
```

---

## 6. API Endpoints (internal)

```
POST /v1/policy/authorize      ← dari FreeRADIUS rlm_rest
POST /v1/policy/accounting     ← dari FreeRADIUS rlm_rest
POST /v1/policy/post-auth      ← dari FreeRADIUS rlm_rest
POST /v1/coa/send              ← trigger CoA ke NAS
GET  /health
GET  /health/ready
GET  /metrics                  (Prometheus)
```

---

## 7. FreeRADIUS rlm_rest Config

```apacheconf
authorize {
  uri = "${..connect_uri}/v1/policy/authorize"
  method = 'post'
  body = 'json'
  data = '{
    "username": "%{User-Name}",
    "User-Password": "%{User-Password}",
    "NAS-IP-Address": "%{NAS-IP-Address}",
    "NAS-Port": "%{NAS-Port}",
    "Called-Station-Id": "%{Called-Station-Id}",
    "Calling-Station-Id": "%{Calling-Station-Id}",
    "Service-Type": "%{Service-Type}",
    "EAP-Type": "%{EAP-Type}",
    "Acct-Session-Id": "%{Acct-Session-Id}"
  }'
}
```

---

## 8. AI Anomaly Detection

oxRADIUS terintegrasi dengan Python AI microservice (FastAPI) untuk deteksi anomali berbasis Isolation Forest / LSTM Autoencoder.

```gleam
pub type AnomalyAction {
  Allow
  Flag    // izinkan tapi alert ke admin
  Block   // tolak + trigger CoA disconnect
}
```

Flow:
```
accounting_pipeline
    ↓ (setiap Accounting-Stop + Interim)
ai_fraud_client (Gleam) → Python AI Service
    ↓ AnomalyScore
policy_engine (blokir jika score > 0.85)
notification_engine (alert admin via Telegram/WA)
```

---

## 9. Subscriber Management

### Endpoints

```
GET    /v1/subscribers
POST   /v1/subscribers
POST   /v1/subscribers/import      bulk import CSV
GET    /v1/subscribers/export
POST   /v1/subscribers/generate    bulk generate voucher-style
GET    /v1/subscribers/:id
PATCH  /v1/subscribers/:id
DELETE /v1/subscribers/:id
POST   /v1/subscribers/:id/reset-password
POST   /v1/subscribers/:id/lock
POST   /v1/subscribers/:id/unlock
POST   /v1/subscribers/:id/reset-quota
POST   /v1/subscribers/:id/coa
POST   /v1/subscribers/:id/disconnect
GET    /v1/subscribers/:id/sessions
GET    /v1/subscribers/:id/accounting
GET    /v1/subscribers/:id/gdpr/export
DELETE /v1/subscribers/:id/gdpr/erase
```

### Auth Methods yang Didukung
- PAP, CHAP, MS-CHAPv2
- EAP-PEAP, EAP-TLS
- MAC Auth Bypass (MAB)
- Voucher Auth

### daloRADIUS Compatibility Endpoints

```
POST /v1/migration/dalo/validate-connection
POST /v1/migration/dalo/preview-mapping
POST /v1/migration/dalo/dry-run
POST /v1/migration/dalo/import
POST /v1/migration/dalo/rollback
```

Sumber migrasi awal diprioritaskan dari MySQL/MariaDB (instalasi umum daloRADIUS), kemudian dinormalisasi ke schema PostgreSQL 18 Oxion.

---

## 10. Package & FUP

```gleam
pub type ServicePackage {
  ServicePackage(
    id: String,
    name: String,
    download_kbps: Int,
    upload_kbps: Int,
    quota_bytes: Option(Int),        // None = unlimited
    fup_threshold_bytes: Option(Int),
    fup_download_kbps: Int,
    fup_upload_kbps: Int,
    validity_days: Option(Int),
    simultaneous_use: Int,
    time_windows: List(TimeWindow),
    custom_vsa: List(VsaAttribute),
  )
}

pub type CollectionThrottleProfile {
  CollectionThrottleProfile(
    id: String,
    download_kbps: Int,
    upload_kbps: Int,
    reason: String,
  )
}
```

### Profile Throttle dari Policy

```text
id: bw_4mbps_sample
download_kbps: 4096
upload_kbps: 4096
reason: overdue_collection
```

Nilai profile tidak hardcoded di core; profile dipilih oleh collection policy per tenant.

### CoA Idempotency Guard

Untuk mencegah CoA berulang setiap hari pada profile yang sama:

- Simpan `last_enforced_profile_id` per subscriber di cache + DB snapshot.
- Saat menerima request `change-package` ke profile policy (`profile_id`), bandingkan dengan profile aktif.
- Jika profile aktif sudah sama, skip `send_coa` dan catat sebagai `idempotent_skip`.

---

## 11. Database Schema

```sql
CREATE TABLE subscribers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id) NOT NULL,
  reseller_id     UUID REFERENCES resellers(id),
  username        TEXT NOT NULL,
  password_hash   TEXT,
  password_type   TEXT DEFAULT 'bcrypt',
  mac_addresses   TEXT[] DEFAULT '{}',
  package_id      UUID REFERENCES packages(id),
  vlan_id         INT,
  static_ip       INET,
  account_expiry  TIMESTAMPTZ,
  auth_methods    TEXT[] DEFAULT '{"pap"}',
  active          BOOLEAN DEFAULT true,
  locked          BOOLEAN DEFAULT false,
  fraud_score     NUMERIC(4,3) DEFAULT 0.0,
  anomaly_flags   TEXT[] DEFAULT '{}',
  UNIQUE(tenant_id, username)
);

CREATE TABLE quota_states (
  subscriber_id UUID REFERENCES subscribers(id),
  period_start  TIMESTAMPTZ NOT NULL,
  period_end    TIMESTAMPTZ NOT NULL,
  used_bytes    BIGINT NOT NULL DEFAULT 0,
  is_fup_active BOOLEAN DEFAULT false,
  fup_triggered_at TIMESTAMPTZ,
  PRIMARY KEY (subscriber_id, period_start)
);

CREATE TABLE active_sessions (
  session_id    TEXT PRIMARY KEY,
  tenant_id     UUID NOT NULL,
  subscriber_id UUID,
  nas_id        UUID,
  framed_ip     INET,
  mac_address   TEXT,
  started_at    TIMESTAMPTZ NOT NULL,
  last_interim  TIMESTAMPTZ,
  input_bytes   BIGINT DEFAULT 0,
  output_bytes  BIGINT DEFAULT 0,
  session_time  INT DEFAULT 0
);

-- TimescaleDB hypertable untuk traffic stats
CREATE TABLE traffic_stats (
  time          TIMESTAMPTZ NOT NULL,
  subscriber_id UUID NOT NULL,
  nas_id        UUID,
  download_bytes BIGINT DEFAULT 0,
  upload_bytes   BIGINT DEFAULT 0,
  session_count  INT DEFAULT 0
);
SELECT create_hypertable('traffic_stats', 'time');
```

---

## 12. Deployment (Kubernetes)

```yaml
# FreeRADIUS sebagai DaemonSet
kind: DaemonSet
nodeSelector:
  role: access-node
hostNetwork: true   # akses UDP 1812/1813 langsung

# oxRADIUS API
autoscaling:
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

---

## 13. Prometheus Metrics

```
aaa_authorize_total{tenant_id, result}
aaa_authorize_duration_ms{quantile}
aaa_accounting_total{tenant_id, type}
aaa_active_sessions{tenant_id, nas_id}
aaa_quota_exhausted_total{tenant_id}
aaa_fup_activated_total{tenant_id}
aaa_anomaly_detected_total{tenant_id, action}
aaa_fraud_score_histogram{tenant_id}
erlang_vm_process_count
erlang_vm_memory_bytes{kind}
erlang_vm_scheduler_utilization
```

---

## 14. Keamanan

- Komunikasi FreeRADIUS ↔ oxRADIUS via mTLS
- RadSec (RADIUS over TLS) untuk lintas-domain
- API Key auth untuk internal (rlm_rest)
- JWT dari ZITADEL untuk dashboard/UI
- AES-256-GCM untuk enkripsi credentials NAS
- GDPR: anonymization via `/gdpr/erase`
