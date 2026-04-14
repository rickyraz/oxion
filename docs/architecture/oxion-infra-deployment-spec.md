# oxion  Infrastructure, Deployment & Roadmap

**Cakupan:** Stack Teknologi, Struktur Monorepo, Data Model PostgreSQL Lengkap, Kontrak API Lengkap, Keamanan & Transport, High Availability & Kubernetes, UI Layer, Roadmap Implementasi, Feature Coverage Matrix

## 1. Dokumen Terkait

- [Platform Overview](oxion-platform-overview.md)
- [Platform Services Specification](oxion-platform-services-spec.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)
- [oxCore Spec](../modules/oxcore-spec.md)
- [oxOLT Spec](../modules/oxolt-spec.md)
- [oxBill Spec](../modules/oxbill-spec.md)
- [oxNOC Spec](../modules/oxnoc-spec.md)
- [Brand Naming](oxion-brand-naming.md)
- [Plugin Architecture](../plugins/oxion-plugin-architecture.md)
- [Plugin Examples](../plugins/oxion-plugin-examples.md)
- [Collection Policy Schema](../policies/collection-policy.schema.json)
- [Collection Policy EBNF](../policies/collection-policy-ebnf.md)
- [Tier-1 Broadband Interop Profile](../interoperability/oxion-tier1-broadband-interoperability-profile.md)
- [dalo Migration Runbook](../operations/oxion-dalo-migration-runbook.md)
- [Connect BEAM Adapter Roadmap](../implementation/connect-beam-adapter-roadmap.md)

---

## 2. Stack Teknologi

| Layer               | Teknologi                                      | Versi / Catatan                                                                                |
| ------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| RADIUS Server       | **FreeRADIUS (hybrid) + Gleam logic**          | FreeRADIUS difokuskan sebagai UDP front-end + `rlm_rest`; seluruh logic utama berjalan di BEAM |
| Policy Engine       | **Gleam** + gleam_otp                          | 1.x, berjalan di BEAM VM                                                                       |
| HTTP Server         | **Wisp** + Mist (Gleam)                        | REST + SSE                                                                                     |
| Future Typed API    | **connect-beam** + connect-es + connect-query  | Planned Connect-style RPC adapter untuk operator/internal UI; REST tetap baseline              |
| GraphQL             | **Absinthe** via Erlang interop                | Subscription melalui WebSocket                                                                 |
| WebSocket           | **Bandit** + Phoenix.Channels interop          | real-time events                                                                               |
| Cache In-Process    | **ETS** via Nebulex local adapter              | TTL 30 detik                                                                                   |
| Cache Distributed   | **Nebulex** (shards adapter) + BEAM clustering | TTL 300 detik, distribusi antar node berbasis daftar cluster                                   |
| Message Broker      | **NATS JetStream**                             | event sourcing, accounting, notif                                                              |
| Database Primary    | **PostgreSQL 18** via pgo                      | subscriber, billing, config                                                                    |
| Database TimeSeries | **TimescaleDB** (PostgreSQL ext)               | traffic stats, accounting                                                                      |
| Object Storage      | **Gleam bucket   Cloudflare R2 / Backblaze**   | Invoice PDF, firmware, export CSV; **Garage** sebagai opsi self-hosted                         |
| Notification        | **Gleam** notification_engine                  | WhatsApp/Telegram/SMS/Email/Push                                                               |
| SSO / Identity      | **ZITADEL**                                    | Mendukung OIDC, SAML 2.0, OAuth2; lebih ringan untuk operasional                               |
| AI/ML               | **Nx + Scholar (Elixir)** atau Python fallback | Anomaly detection, termasuk inference Isolation Forest                                         |
| Plugin Runtime      | **Oxion Plugin Runner**                        | Eksekusi plugin terisolasi (TypeScript/Python/Elixir), tenant-scoped, dengan quota + audit    |
| NAS Provisioning    | **Gleam** nas_provisioner                      | SNMP + SSH + REST per vendor                                                                   |
| GIS                 | **PostGIS** + OpenStreetMap tiles              | lokasi AP/NAS di peta                                                                          |
| Payment             | **Midtrans / Xendit / Stripe** adapter         | lokal + global                                                                                 |
| Crypto Payment      | **NOWPayments API** + QRIS                     | USDT/BTC/ETH/QRIS                                                                              |
| Firmware OTA        | **Gleam** ota_scheduler                        | MikroTik API + OpenWrt OWUT                                                                    |
| UI Framework        | **TanStack Start** + **SolidJS**               | SSR + file-based routing                                                                       |
| UI Charts           | **Chart.js / ECharts** via SolidJS             | grafis report                                                                                  |
| UI Maps             | **Leaflet.js**                                 | OpenStreetMap GIS                                                                              |
| Mobile App          | **React Native + Expo**                        | Android + iOS                                                                                  |
| Observability       | **Prometheus + Grafana + Loki + Tempo**        | full observability stack                                                                       |
| Deployment          | **Kubernetes** + Helm + ArgoCD                 | GitOps                                                                                         |

### Profil Produk & Deployment

Oxion memiliki dua profil operasi dalam satu codebase: **Lite Mode** untuk skenario kecil (gaya panel FreeRADIUS seperti daloRADIUS) dan **Platform Mode** untuk skenario enterprise.

| Profil | Target Skenario | Paket Deploy | Modul Aktif Default | Catatan |
| --- | --- | --- | --- | --- |
| **Lite Mode** | ISP kecil / single POP / lab | Docker Compose (single VM) | oxRADIUS + panel subscriber/NAS/profile/accounting/voucher | UI default sederhana, advanced modules via feature flag |
| **Platform Mode** | Multi-tenant / reseller / enterprise | Kubernetes + Helm + ArgoCD | Semua modul (oxRADIUS, oxCore, oxOLT, oxBill, oxNOC) | HA, autoscaling, GitOps, observability penuh |

Prinsip produk: **simple by default, powerful by choice**.

### Kompatibilitas daloRADIUS & Jalur Migrasi

Untuk adopsi awal yang cepat, Oxion menyediakan mode kompatibilitas daloRADIUS:

- Import schema operasional daloRADIUS (`radcheck`, `radreply`, `radacct`, `nas`, `radusergroup`).
- Wizard migrasi: koneksi DB lama -> mapping field -> dry-run -> apply.
- Rollback snapshot sebelum cutover.

Strategi database:

1. **Tahap adopsi awal:** kompatibilitas sumber data **MySQL/MariaDB** (umum pada instalasi daloRADIUS).
2. **Tahap stabilisasi:** migrasi terstruktur ke **PostgreSQL 18** sebagai database utama Oxion.

---

## 3. Struktur Monorepo

### Struktur Aktual (April 2026)

```text
oxion/
|-- apps/
|   |-- oxradius/
|   |-- oxcore/
|   |-- oxnoc/
|   |-- oxbill/
|   `-- oxolt/
|-- packages/
|   |-- policy/
|   `-- interop/
|-- frontend/
|   `-- platform/
|-- schema/
|-- generated/
|-- scripts/
|-- tools/
|-- docs/
|-- package.json
|-- pnpm-workspace.yaml
`-- turbo.json
```

### Boundary Lintas Package

- `packages/policy` memegang kontrak policy (`types`, `validator`, `evaluator`, `simulator`, `lifecycle`) dan harus tetap deterministic.
- `apps/oxcore` memegang runtime collection + orchestration (`collection`, `orchestration/collection`).
- `apps/oxradius` memegang transport/protocol RADIUS (`packet`, `coa`, `disconnect`, `dictionary`, `registry`, `session`, `udp`, `radsec`).
- `apps/oxnoc` memegang audit + DSR workflow (`platform/audit`, `platform/dsr`).
- `packages/interop` dipakai untuk contract lintas app (misalnya `oxion/radius/coa/result.gleam`).
- `frontend/platform` adalah UI TanStack Start untuk operator dashboard saat ini.

### Ekspansi Terencana (Belum Aktif di Repo)

- `frontend/mobile/` untuk React Native + Expo.
- `infra/` untuk helm chart, compose profile, dan manifest deployment.
- `services/` untuk microservice eksternal (contoh AI anomaly) bila dipisah dari BEAM apps.

Catatan boundary API (do one thing well):

- `api_gateway` hanya routing, auth middleware, rate limit, dan tracing.
- `*_api` modules memegang domain handler sesuai bounded context.
- `gateway` tidak boleh berisi business rule domain; semua rule tetap di engine domain terkait.

---

## 4. Data Model Lengkap PostgreSQL

```sql
-- """""""""""""""""""""""""""""""""""""""""""""""
-- EXTENSIONS
-- """""""""""""""""""""""""""""""""""""""""""""""
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- """""""""""""""""""""""""""""""""""""""""""""""
-- MULTI-TENANT
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE tenants (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            TEXT UNIQUE NOT NULL,
  name            TEXT NOT NULL,
  custom_domain   TEXT UNIQUE,
  branding        JSONB DEFAULT '{}',
  features        JSONB DEFAULT '{}',
  plan            TEXT NOT NULL DEFAULT 'starter',
  max_subscribers INT,
  max_nas         INT,
  active          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- OPERATORS / RESELLERS
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE resellers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id) NOT NULL,
  parent_id       UUID REFERENCES resellers(id),
  name            TEXT NOT NULL,
  subdomain       TEXT,
  branding        JSONB DEFAULT '{}',
  credit_balance  BIGINT DEFAULT 0,
  credit_limit    BIGINT DEFAULT 0,
  discount_pct    NUMERIC(5,2) DEFAULT 0,
  commission_rate NUMERIC(5,2) DEFAULT 0,
  active          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE operators (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID REFERENCES tenants(id) NOT NULL,
  reseller_id   UUID REFERENCES resellers(id),
  username      TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  email         TEXT,
  role          TEXT NOT NULL,
  permissions   TEXT[] DEFAULT '{}',
  active        BOOLEAN DEFAULT true,
  last_login    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- PACKAGES
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE packages (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            UUID REFERENCES tenants(id) NOT NULL,
  name                 TEXT NOT NULL,
  display_name         TEXT,
  download_kbps        INT NOT NULL,
  upload_kbps          INT NOT NULL,
  quota_bytes          BIGINT,
  fup_threshold_bytes  BIGINT,
  fup_download_kbps    INT DEFAULT 0,
  fup_upload_kbps      INT DEFAULT 0,
  validity_days        INT,
  simultaneous_use     INT DEFAULT 1,
  time_windows         JSONB DEFAULT '[]',
  custom_vsa           JSONB DEFAULT '[]',
  billing_plan         JSONB DEFAULT '{}',
  active               BOOLEAN DEFAULT true,
  UNIQUE(tenant_id, name)
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- SUBSCRIBERS
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE subscribers (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID REFERENCES tenants(id) NOT NULL,
  reseller_id      UUID REFERENCES resellers(id),
  username         TEXT NOT NULL,
  password_hash    TEXT,
  password_type    TEXT DEFAULT 'bcrypt',
  display_name     TEXT,
  email            TEXT,
  phone            TEXT,
  mac_addresses    TEXT[] DEFAULT '{}',
  package_id       UUID REFERENCES packages(id),
  vlan_id          INT,
  static_ip        INET,
  custom_vsa       JSONB DEFAULT '[]',
  nas_whitelist    TEXT[],
  account_expiry   TIMESTAMPTZ,
  auth_methods     TEXT[] DEFAULT '{"pap"}',
  active           BOOLEAN DEFAULT true,
  locked           BOOLEAN DEFAULT false,
  lock_reason      TEXT,
  fraud_score      NUMERIC(4,3) DEFAULT 0.0,
  anomaly_flags    TEXT[] DEFAULT '{}',
  social_provider  TEXT,
  social_id        TEXT,
  kyc_verified     BOOLEAN DEFAULT false,
  consent_given_at TIMESTAMPTZ,
  notes            TEXT,
  tags             TEXT[] DEFAULT '{}',
  created_by       UUID,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, username)
);
CREATE INDEX ON subscribers(tenant_id, active);
CREATE INDEX ON subscribers(tenant_id, reseller_id);
CREATE INDEX ON subscribers(tenant_id, package_id);
CREATE INDEX ON subscribers USING gin(mac_addresses);
CREATE INDEX ON subscribers USING gin(tags);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- QUOTA
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE quota_states (
  subscriber_id    UUID REFERENCES subscribers(id),
  period_start     TIMESTAMPTZ NOT NULL,
  period_end       TIMESTAMPTZ NOT NULL,
  used_bytes       BIGINT NOT NULL DEFAULT 0,
  is_fup_active    BOOLEAN DEFAULT false,
  fup_triggered_at TIMESTAMPTZ,
  PRIMARY KEY (subscriber_id, period_start)
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- NAS DEVICES
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE nas_devices (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID REFERENCES tenants(id) NOT NULL,
  reseller_id         UUID REFERENCES resellers(id),
  name                TEXT NOT NULL,
  ip_address          INET NOT NULL,
  nas_type            TEXT NOT NULL,
  shared_secret       TEXT NOT NULL,
  management_protocol JSONB DEFAULT '{}',
  management_creds    JSONB DEFAULT '{}',   -- MUST be encrypted AES-256-GCM before insert; see Section 6
  location            GEOMETRY(Point, 4326),
  location_name       TEXT,
  firmware_version    TEXT,
  last_seen           TIMESTAMPTZ,
  status              TEXT DEFAULT 'unknown',
  signal_monitoring   BOOLEAN DEFAULT false,
  hotspot_config      JSONB DEFAULT '{}',
  hotspot2_config     JSONB DEFAULT '{}',
  active              BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, ip_address)
);
CREATE INDEX ON nas_devices USING GIST(location);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- SESSIONS + ACCOUNTING
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE active_sessions (
  session_id    TEXT PRIMARY KEY,
  tenant_id     UUID REFERENCES tenants(id) NOT NULL,
  subscriber_id UUID REFERENCES subscribers(id),
  nas_id        UUID REFERENCES nas_devices(id),
  framed_ip     INET,
  mac_address   TEXT,
  started_at    TIMESTAMPTZ NOT NULL,
  last_interim  TIMESTAMPTZ,
  input_bytes   BIGINT DEFAULT 0,
  output_bytes  BIGINT DEFAULT 0,
  session_time  INT DEFAULT 0
);

CREATE TABLE accounting_records (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id) NOT NULL,
  session_id      TEXT NOT NULL,
  subscriber_id   UUID,
  nas_id          UUID,
  event_type      TEXT NOT NULL,
  nas_ip          TEXT NOT NULL,
  framed_ip       INET,
  mac_address     TEXT,
  input_bytes     BIGINT,
  output_bytes    BIGINT,
  session_time    INT,
  terminate_cause TEXT,
  recorded_at     TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON accounting_records(tenant_id, subscriber_id, recorded_at DESC);
CREATE INDEX ON accounting_records(session_id);

-- TimescaleDB hypertables
CREATE TABLE traffic_stats (
  time           TIMESTAMPTZ NOT NULL,
  subscriber_id  UUID NOT NULL,
  nas_id         UUID,
  download_bytes BIGINT DEFAULT 0,
  upload_bytes   BIGINT DEFAULT 0,
  session_count  INT DEFAULT 0
);
SELECT create_hypertable('traffic_stats', 'time');
CREATE INDEX ON traffic_stats(subscriber_id, time DESC);

CREATE TABLE signal_samples (
  time       TIMESTAMPTZ NOT NULL,
  nas_id     UUID NOT NULL,
  onu_id     TEXT,
  interface  TEXT,
  signal_dbm FLOAT,
  noise_dbm  FLOAT,
  snr_db     FLOAT,
  rx_power   FLOAT,
  tx_power   FLOAT,
  status     TEXT
);
SELECT create_hypertable('signal_samples', 'time');

CREATE MATERIALIZED VIEW traffic_daily
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', time) AS bucket,
       subscriber_id,
       sum(download_bytes) AS download_bytes,
       sum(upload_bytes)   AS upload_bytes,
       count(*)            AS session_count
FROM traffic_stats
GROUP BY bucket, subscriber_id;

-- """""""""""""""""""""""""""""""""""""""""""""""
-- ISP CORE SERVICE INVENTORY
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE customers (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_odoo_id TEXT UNIQUE,
  tenant_id        UUID REFERENCES tenants(id),
  full_name        TEXT NOT NULL,
  phone            TEXT,
  email            TEXT,
  status           TEXT DEFAULT 'active',
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE services (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id            UUID NOT NULL REFERENCES customers(id),
  tenant_id              UUID REFERENCES tenants(id),
  package_id             UUID REFERENCES packages(id),
  external_odoo_order_id TEXT,
  service_number         TEXT UNIQUE NOT NULL,
  status                 TEXT NOT NULL CHECK (
    status IN (
      'draft',
      'pending_activation',
      'active',
      'throttled_due_overdue',
      'suspended',
      'terminating',
      'terminated',
      'inconsistent'
    )
  ),
  desired_state          TEXT NOT NULL CHECK (desired_state IN ('active', 'suspended', 'terminated')),
  actual_state           TEXT NOT NULL DEFAULT 'unknown' CHECK (actual_state IN ('active', 'suspended', 'terminated', 'partial', 'unknown')),
  activation_date        TIMESTAMPTZ,
  suspension_reason      TEXT,
  termination_reason     TEXT,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE network_attachments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id       UUID NOT NULL UNIQUE REFERENCES services(id),
  olt_id           UUID REFERENCES nas_devices(id),
  olt_vendor       TEXT,
  pon_fsp          TEXT,
  onu_id           INTEGER,
  onu_serial       TEXT,
  onu_name         TEXT,
  vlan_id          INTEGER,
  gemport_id       INTEGER,
  tcont_id         INTEGER,
  service_port     TEXT,
  line_profile     TEXT,
  service_profile  TEXT,
  provision_status TEXT NOT NULL DEFAULT 'unbound',
  last_sync_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE workflow_jobs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id    UUID REFERENCES services(id),
  tenant_id     UUID REFERENCES tenants(id),
  job_type      TEXT NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('pending', 'running', 'success', 'failed', 'partial')),
  requested_by  TEXT,
  source        TEXT NOT NULL,
  payload       JSONB DEFAULT '{}',
  error_message TEXT,
  retry_count   INTEGER DEFAULT 0,
  started_at    TIMESTAMPTZ,
  finished_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE workflow_steps (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id        UUID NOT NULL REFERENCES workflow_jobs(id),
  step_order    INTEGER NOT NULL,
  step_name     TEXT NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('pending', 'running', 'success', 'failed', 'skipped')),
  payload       JSONB DEFAULT '{}',
  result        JSONB,
  error_message TEXT,
  started_at    TIMESTAMPTZ,
  finished_at   TIMESTAMPTZ
);

CREATE TABLE service_state_snapshots (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id   UUID NOT NULL REFERENCES services(id),
  source       TEXT NOT NULL,
  state        JSONB NOT NULL,
  collected_at TIMESTAMPTZ DEFAULT now()
);

-- """""""""""""""""""""""""""""""""""""""""""""""""""""""
-- PLUGIN RUNTIME (Platform Mode)
-- Detail kontrak/lifecycle: docs/plugins/oxion-plugin-architecture.md
-- """""""""""""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE plugin_manifests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plugin_id         TEXT NOT NULL,
  name              TEXT NOT NULL,
  version           TEXT NOT NULL,
  api_version       TEXT NOT NULL,
  plugin_type       TEXT NOT NULL CHECK (plugin_type IN ('flow', 'policy', 'billing', 'ui', 'integration')),
  runtime_language  TEXT NOT NULL CHECK (runtime_language IN ('typescript', 'python', 'elixir')),
  runtime_version   TEXT,
  hooks             JSONB NOT NULL DEFAULT '[]',
  permissions       JSONB NOT NULL DEFAULT '[]',
  signature         TEXT,
  manifest          JSONB NOT NULL,
  lifecycle_state   TEXT NOT NULL CHECK (lifecycle_state IN ('draft', 'verified', 'enabled_staging', 'enabled_production', 'disabled')),
  uploaded_by       TEXT,
  verified_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plugin_id, version)
);

CREATE TABLE plugin_activations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  manifest_id     UUID NOT NULL REFERENCES plugin_manifests(id),
  scope           TEXT NOT NULL CHECK (scope IN ('global', 'tenant', 'reseller')),
  tenant_id       UUID REFERENCES tenants(id),
  reseller_id     UUID REFERENCES resellers(id),
  status          TEXT NOT NULL CHECK (status IN ('enabled', 'disabled')),
  config          JSONB NOT NULL DEFAULT '{}',
  activated_by    TEXT,
  activated_at    TIMESTAMPTZ DEFAULT now(),
  disabled_at     TIMESTAMPTZ,
  UNIQUE(manifest_id, scope, tenant_id, reseller_id)
);

CREATE TABLE plugin_audit_log (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activation_id    UUID REFERENCES plugin_activations(id),
  tenant_id        UUID REFERENCES tenants(id),
  subscriber_id    UUID REFERENCES subscribers(id),
  hook_name        TEXT NOT NULL,
  decision         TEXT,
  success          BOOLEAN NOT NULL DEFAULT true,
  latency_ms       INTEGER,
  error_message    TEXT,
  emitted_event_id TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON plugin_audit_log(tenant_id, created_at DESC);
CREATE INDEX ON plugin_audit_log(activation_id, created_at DESC);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- VOUCHERS
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE voucher_batches (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          UUID REFERENCES tenants(id) NOT NULL,
  reseller_id        UUID REFERENCES resellers(id),
  name               TEXT NOT NULL,
  package_id         UUID REFERENCES packages(id) NOT NULL,
  count              INT NOT NULL,
  price              BIGINT NOT NULL,
  currency           TEXT DEFAULT 'IDR',
  valid_for_hours    INT NOT NULL,
  expires_after_days INT,
  pdf_url            TEXT,
  created_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE vouchers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id) NOT NULL,
  batch_id        UUID REFERENCES voucher_batches(id) NOT NULL,
  reseller_id     UUID REFERENCES resellers(id),
  code            TEXT NOT NULL,
  qr_data         TEXT NOT NULL,
  package_id      UUID REFERENCES packages(id) NOT NULL,
  price           BIGINT NOT NULL,
  currency        TEXT DEFAULT 'IDR',
  valid_for_hours INT NOT NULL,
  max_uses        INT DEFAULT 1,
  current_uses    INT DEFAULT 0,
  status          TEXT DEFAULT 'active',
  activated_by    UUID REFERENCES subscribers(id),
  activated_at    TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, code)
);
CREATE INDEX ON vouchers(tenant_id, status);
CREATE INDEX ON vouchers(code);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- BILLING
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE invoices (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         UUID REFERENCES tenants(id) NOT NULL,
  subscriber_id     UUID NOT NULL REFERENCES subscribers(id),
  reseller_id       UUID REFERENCES resellers(id),
  invoice_number    TEXT UNIQUE NOT NULL,
  period_start      DATE,
  period_end        DATE,
  line_items        JSONB DEFAULT '[]',
  subtotal          BIGINT NOT NULL,
  tax               BIGINT DEFAULT 0,
  total             BIGINT NOT NULL,
  currency          TEXT DEFAULT 'IDR',
  status            TEXT DEFAULT 'draft',
  payment_method    TEXT,
  payment_reference TEXT,
  paid_at           TIMESTAMPTZ,
  due_date          DATE,
  pdf_url           TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON invoices(tenant_id, subscriber_id, created_at DESC);
CREATE INDEX ON invoices(status);

CREATE TABLE payment_methods_on_file (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id  UUID NOT NULL REFERENCES subscribers(id),
  type           TEXT NOT NULL,
  provider_token TEXT NOT NULL,
  is_default     BOOLEAN DEFAULT false,
  expires_at     DATE,
  created_at     TIMESTAMPTZ DEFAULT now()
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- PUSH TOKENS
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE push_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id UUID NOT NULL REFERENCES subscribers(id),
  token         TEXT NOT NULL,
  platform      TEXT NOT NULL,
  registered_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(subscriber_id, token)
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- AUDIT LOG (append-only, redacted, long-retention)
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE audit_log (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID NOT NULL,
  actor_id         UUID,
  actor_role       TEXT NOT NULL,
  action           TEXT NOT NULL,
  resource_type    TEXT NOT NULL,
  resource_ref     TEXT,
  subject_ref      UUID,
  subject_alias    TEXT,
  change_summary   JSONB NOT NULL DEFAULT '{}'::jsonb,
  privacy_class    TEXT NOT NULL,
  retention_class  TEXT NOT NULL,
  legal_basis      TEXT NOT NULL,
  success          BOOLEAN NOT NULL,
  error_code       TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON audit_log(tenant_id, created_at DESC);
CREATE INDEX ON audit_log(subject_alias, created_at DESC);
CREATE INDEX ON audit_log(resource_type, resource_ref);

CREATE TABLE audit_private_context (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id          UUID UNIQUE NOT NULL REFERENCES audit_log(id),
  purpose           TEXT NOT NULL,
  encrypted_payload BYTEA NOT NULL,
  key_version       TEXT NOT NULL,
  expires_at        TIMESTAMPTZ NOT NULL,
  erased_at         TIMESTAMPTZ
);
CREATE INDEX ON audit_private_context(expires_at);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- CONSENT (GDPR)
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE consent_records (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id  UUID NOT NULL,
  tenant_id      UUID REFERENCES tenants(id) NOT NULL,
  consent_type   TEXT NOT NULL,
  policy_version TEXT NOT NULL,
  given_at       TIMESTAMPTZ NOT NULL,
  ip_fingerprint BYTEA,
  evidence_ref   UUID,
  revoked_at     TIMESTAMPTZ
);

CREATE TABLE data_subject_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID NOT NULL,
  subject_ref         UUID NOT NULL,
  request_type        TEXT NOT NULL,
  status              TEXT NOT NULL,
  requested_by_actor  UUID,
  legal_hold          BOOLEAN NOT NULL DEFAULT FALSE,
  reason              TEXT,
  submitted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at        TIMESTAMPTZ
);

CREATE TABLE data_subject_request_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dsr_id              UUID NOT NULL REFERENCES data_subject_requests(id),
  store_name          TEXT NOT NULL,
  action              TEXT NOT NULL,
  status              TEXT NOT NULL,
  resolution_note     TEXT,
  executed_at         TIMESTAMPTZ
);
CREATE INDEX ON data_subject_request_items(dsr_id, store_name);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- FIRMWARE
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE firmware_repository (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nas_type        TEXT NOT NULL,
  version         TEXT NOT NULL,
  release_date    DATE,
  download_url    TEXT NOT NULL,
  checksum_sha256 TEXT NOT NULL,
  release_notes   TEXT,
  is_stable       BOOLEAN DEFAULT true,
  is_security     BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(nas_type, version)
);

CREATE TABLE firmware_upgrades (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id),
  nas_id          UUID REFERENCES nas_devices(id) NOT NULL,
  current_version TEXT,
  target_version  TEXT NOT NULL,
  firmware_id     UUID REFERENCES firmware_repository(id),
  scheduled_at    TIMESTAMPTZ,
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  status          TEXT DEFAULT 'scheduled',
  error_msg       TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- """""""""""""""""""""""""""""""""""""""""""""""
-- LOGIN PAGES
-- """""""""""""""""""""""""""""""""""""""""""""""

CREATE TABLE login_pages (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID REFERENCES tenants(id) NOT NULL,
  reseller_id    UUID REFERENCES resellers(id),
  name           TEXT NOT NULL,
  html_template  TEXT NOT NULL,
  css_override   TEXT,
  logo_url       TEXT,
  background_url TEXT,
  primary_color  TEXT DEFAULT '#1a73e8',
  social_buttons TEXT[] DEFAULT '{}',
  languages      TEXT[] DEFAULT '{"id","en"}',
  is_default     BOOLEAN DEFAULT false,
  created_at     TIMESTAMPTZ DEFAULT now()
);
```

---

## 5. Kontrak API Lengkap

Kontrak REST di bawah ini adalah baseline saat ini. Ke depan, Oxion akan menambahkan **connect-beam** sebagai adapter Connect-style RPC untuk API operator/internal yang butuh typed request/response, error model konsisten, dan integrasi lebih natural dengan TanStack Start via `connect-es` + `connect-query`.

Strategi evolusi:

- REST tetap dipakai untuk health, metrics, webhooks, endpoint publik sederhana, file export/download, dan kompatibilitas eksternal.
- Connect RPC dipakai bertahap untuk domain action/query yang kompleks: subscribers, services, NAS/ONU, billing, reports.
- `api_gateway` tetap tipis: auth, tenant resolution, rate limit, tracing, decode/encode; business rule tetap di domain Gleam/BEAM.
- Detail roadmap: [Connect BEAM Adapter Roadmap](../implementation/connect-beam-adapter-roadmap.md).

```
#  RADIUS (internal, dari FreeRADIUS) 
POST /v1/policy/authorize
POST /v1/policy/accounting
POST /v1/policy/post-auth

#  HEALTH 
GET  /health
GET  /health/ready
GET  /metrics                    (Prometheus, internal only)

#  AUTH 
GET  /auth/login
GET  /auth/callback
POST /auth/logout
POST /auth/token/refresh

#  SELF-SERVICE (publik / UCP + mobile) 
POST /v1/self/register
POST /v1/self/verify/sms
POST /v1/self/verify/email
GET  /v1/self/profile
PUT  /v1/self/profile
POST /v1/self/change-password
GET  /v1/self/quota
GET  /v1/self/sessions
POST /v1/self/voucher/redeem
GET  /v1/self/invoices
POST /v1/self/topup
POST /v1/self/push-token

#  SUBSCRIBERS (oxRADIUS) 
GET    /v1/subscribers
POST   /v1/subscribers
POST   /v1/subscribers/import
GET    /v1/subscribers/export
POST   /v1/subscribers/bulk-generate
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
GET    /v1/subscribers/:id/invoices

#  PACKAGES 
GET    /v1/packages
POST   /v1/packages
GET    /v1/packages/:id
PUT    /v1/packages/:id
DELETE /v1/packages/:id

#  VOUCHERS (oxBill) 
GET    /v1/voucher-batches
POST   /v1/voucher-batches
GET    /v1/voucher-batches/:id
GET    /v1/voucher-batches/:id/vouchers
GET    /v1/voucher-batches/:id/pdf
POST   /v1/vouchers/redeem
GET    /v1/vouchers/:code
DELETE /v1/vouchers/:id

#  BILLING (oxBill) 
GET    /v1/invoices
POST   /v1/invoices
GET    /v1/invoices/:id
GET    /v1/invoices/:id/pdf
POST   /v1/invoices/:id/pay
POST   /v1/invoices/:id/cancel
GET    /v1/collection/policies
POST   /v1/collection/policies
PUT    /v1/collection/policies/:id
POST   /v1/collection/policies/:id/simulate
POST   /v1/collection/policies/:id/publish
POST   /v1/collection/enforce/run
GET    /v1/payments
POST   /v1/payments/webhook/midtrans
POST   /v1/payments/webhook/xendit
POST   /v1/payments/webhook/stripe
POST   /v1/payments/webhook/nowpayments

#  NAS DEVICES (oxOLT) 
GET    /v1/nas
POST   /v1/nas
GET    /v1/nas/:id
PUT    /v1/nas/:id
DELETE /v1/nas/:id
POST   /v1/nas/:id/provision
POST   /v1/nas/:id/deprovision
POST   /v1/nas/:id/test-connection
GET    /v1/nas/:id/sessions
GET    /v1/nas/:id/signal
POST   /v1/nas/:id/firmware/upgrade

#  ONU (oxOLT) 
GET    /v1/onu
GET    /v1/onu/:id
GET    /v1/onu/unconfigured
POST   /v1/onu/:id/configure
POST   /v1/onu/:id/reset
DELETE /v1/onu/:id

#  COA / POD (oxRADIUS) 
POST /v1/coa/send

#  SERVICES (oxCore) 
GET    /v1/services
GET    /v1/services/:id
GET    /v1/services/:id/state
GET    /v1/services/:id/workflows
POST   /v1/services/:id/activate
POST   /v1/services/:id/suspend
POST   /v1/services/:id/terminate
POST   /v1/services/:id/reconcile
POST   /v1/services/:id/change-package
GET    /v1/customers
GET    /v1/customers/:id
GET    /v1/customers/:id/services

#  ODOO WEBHOOKS (oxCore) 
POST   /v1/webhooks/odoo/payment-received
POST   /v1/webhooks/odoo/invoice-overdue
POST   /v1/webhooks/odoo/terminate-request
POST   /v1/webhooks/odoo/service-created
POST   /v1/webhooks/odoo/package-changed

#  RESELLERS 
GET    /v1/resellers
POST   /v1/resellers
GET    /v1/resellers/:id
PUT    /v1/resellers/:id
GET    /v1/resellers/:id/subscribers
GET    /v1/resellers/:id/stats
GET    /v1/resellers/:id/commissions

#  TENANTS (superadmin only) 
GET    /v1/tenants
POST   /v1/tenants
GET    /v1/tenants/:id
PUT    /v1/tenants/:id

#  GIS (oxOLT + oxNOC) 
GET    /v1/gis/nas            (GeoJSON FeatureCollection)
GET    /v1/gis/coverage       (coverage polygons)

#  REPORTS (oxNOC) 
GET    /v1/reports/overview
GET    /v1/reports/traffic/subscriber/:id
GET    /v1/reports/top-users
GET    /v1/reports/nas-utilization
GET    /v1/reports/revenue
GET    /v1/reports/signal/:nas_id
GET    /v1/reports/workflow-summary
GET    /v1/reports/export

#  NOTIFICATIONS 
GET    /v1/notifications/templates
POST   /v1/notifications/send
POST   /v1/notifications/bulk
GET    /v1/notifications/history

#  LOGIN PAGES 
GET    /v1/login-pages
POST   /v1/login-pages
GET    /v1/login-pages/:id
PUT    /v1/login-pages/:id
DELETE /v1/login-pages/:id

#  FIRMWARE (oxOLT) 
GET    /v1/firmware
POST   /v1/firmware
GET    /v1/firmware/upgrades
POST   /v1/firmware/upgrades/:id/schedule
GET    /v1/firmware/upgrades/:id

#  AUDIT (oxNOC) 
GET    /v1/audit-log
POST   /v1/data-subject-requests
GET    /v1/data-subject-requests/:id
POST   /v1/data-subject-requests/:id/verify
POST   /v1/data-subject-requests/:id/cancel
GET    /v1/subscribers/:id/gdpr/export
POST   /v1/subscribers/:id/gdpr/erasure-requests
GET    /v1/subscribers/:id/consent
POST   /v1/subscribers/:id/consent
DELETE /v1/subscribers/:id/consent/:type

#  GRAPHQL 
POST   /graphql
GET    /graphql/subscriptions    (WebSocket upgrade)
```

---

## 6. Keamanan & Transport

### RADIUS Transport

- **RadSec** (RADIUS over TLS/TCP) untuk komunikasi lintas-domain dan lintas-datacenter
- **RADIUS/1.1** dengan HMAC-SHA256 message authentication
- Shared secret minimal 32 karakter, rotasi berkala via Vault/Kubernetes secret

### API Security

- **mTLS** antara FreeRADIUS -> oxRADIUS API
- **JWT (ZITADEL PKCE)** untuk semua web/mobile client - tidak ada client_secret di browser
- **API Key** untuk komunikasi internal service-to-service
- Rate limiting per tenant via Nebulex distributed cache sliding window
- Request signing untuk webhook callbacks (HMAC-SHA256 per provider)

### Data Security

- `management_creds` NAS diencrypt AES-256-GCM sebelum disimpan ke DB
- Payment provider tokens tersimpan sebagai tokenized reference - tidak ada raw card number
- Password subscriber: bcrypt (cost 12) atau PBKDF2
- PDF invoice di Cloudflare R2 / Backblaze menggunakan signed URL dengan TTL 1 jam
- DSR diproses via workflow request dengan identity verification, legal-hold check, dan store-level execution
- Audit log utama bersifat append-only dan redacted; PII sensitif ditempatkan di encrypted short-retention side store

### Kubernetes Secrets

```yaml
# Secrets dikelola via Vault atau Sealed Secrets (GitOps-safe)
apiVersion: v1
kind: Secret
metadata:
  name: oxion-secrets
data:
  database-url:        <base64>
  nebulex-cluster-nodes: <base64>
  nats-url:            <base64>
  radius-api-key:      <base64>
  zitadel-client-secret: <base64>
  object-storage-access-key: <base64>
  object-storage-secret-key: <base64>
```

---

## 7. High Availability & Kubernetes

Catatan repositori: contoh path `infra/...` pada section ini adalah target struktur deployment manifest ketika folder infra diaktifkan kembali di monorepo.

### oxRADIUS API (Gleam)

```yaml
# infra/k8s/helm/oxradius/values.yaml

replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: External
      external:
        metric:
          name: aaa_authorize_duration_ms_p95
          selector:
            matchLabels:
              service: oxradius
        target:
          type: AverageValue
          averageValue: "40"

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi

podDisruptionBudget:
  minAvailable: 1

livenessProbe:
  httpGet: {path: /health, port: 8080}
readinessProbe:
  httpGet: {path: /health/ready, port: 8080}
```

### FreeRADIUS DaemonSet

```yaml
# infra/k8s/helm/freeradius/values.yaml

kind: DaemonSet
nodeSelector:
  role: access-node
hostNetwork: true           # UDP 1812/1813 langsung
dnsPolicy: ClusterFirstWithHostNet
tolerations:
  - operator: Exists
volumes:
  - name: config
    configMap: {name: freeradius-config}
  - name: certs
    secret: {secretName: freeradius-tls}   # RadSec certs
```

### oxCore + oxBill

```yaml
# infra/k8s/helm/oxcore/values.yaml
replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
```

### PostgreSQL (CloudNativePG)

```yaml
kind: Cluster   # CloudNativePG CRD
spec:
  instances: 3                    # 1 primary + 2 replica
  storage:
    size: 100Gi
    storageClass: premium-rwo
  postgresql:
    parameters:
      shared_buffers: "256MB"
      max_connections: "200"
      wal_level: replica
  backup:
    retentionPolicy: "30d"
    barmanObjectStore:
      destinationPath: s3://backups/postgres
```

### Nebulex Distributed Cache

```yaml
# Nebulex local cache: ETS adapter (TTL 30 detik)
# Nebulex distributed cache: shards adapter + BEAM clustering (TTL 300 detik)
# Distribusi antar node mengikuti daftar node cluster BEAM
```

### NATS JetStream

```yaml
# infra/k8s/helm/nats/values.yaml
cluster:
  enabled: true
  replicas: 3

jetstream:
  enabled: true
  memStorage:
    enabled: true
    size: 1Gi
  fileStorage:
    enabled: true
    size: 20Gi
```

### AI Anomaly Microservice

```yaml
# infra/k8s/helm/ai-anomaly/values.yaml
replicaCount: 2
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
autoscaling:
  minReplicas: 2
  maxReplicas: 5
```

---

## 8. UI Layer  TanStack Start + SolidJS

### Routing Lengkap

```
frontend/platform/src/routes/
S index.tsx                    # Dashboard: stats, live sessions, revenue
S subscribers/
   S index.tsx                # List + search + filter
   S $id/
      S index.tsx            # Detail: quota gauge, sessions, history
      S billing.tsx
      S sessions.tsx
       audit.tsx
    new.tsx
S vouchers/
   S index.tsx
   S $batchId.tsx
    new.tsx
S billing/
   S index.tsx
   S $id.tsx
    payments.tsx
S packages/
   S index.tsx
    $id.tsx
S services/                    # oxCore service inventory
   S index.tsx                # List + filter by state
   S $id/
      S index.tsx            # Service detail: 3 state dimensions
       workflow.tsx         # Workflow job history + step detail
    new.tsx
S nas/
   S index.tsx
   S $id/
      S index.tsx
      S sessions.tsx
      S signal.tsx
       firmware.tsx
    new.tsx
S gis/
    index.tsx                # Leaflet map: NAS + coverage
S resellers/
   S index.tsx
    $id.tsx
S reports/
   S index.tsx
   S traffic.tsx
   S revenue.tsx
    top-users.tsx
S notifications/
   S index.tsx
    bulk.tsx
S sessions/
    index.tsx                # Real-time active sessions (WebSocket)
S firmware/
    index.tsx
S audit/
    index.tsx
 system/
    S health.tsx
    S metrics.tsx              # Embedded Grafana iframe
     settings.tsx
```

### Real-time Live Session Table

```tsx
// frontend/platform/src/components/realtime/LiveSessionTable.tsx
import { createSignal, onCleanup, For } from "solid-js";
import type { Session } from "~/api/types";

export function LiveSessionTable(props: { tenantId: string }) {
  const [sessions, setSessions] = createSignal<Session[]>([]);

  const ws = new WebSocket(`${import.meta.env.VITE_WS_URL}/graphql/subscriptions`);

  ws.onopen = () => {
    ws.send(JSON.stringify({
      type: "subscribe",
      payload: {
        query: `subscription { sessionUpdated(tenantId: "${props.tenantId}") {
          sessionId username nasIp framedIp inputBytes outputBytes startedAt
        }}`
      }
    }));
  };

  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === "next") {
      const updated = msg.payload.data.sessionUpdated;
      setSessions(prev => upsert(prev, updated, s => s.sessionId));
    }
  };

  onCleanup(() => ws.close());

  return (
    <table class="live-session-table">
      <thead>
        <tr>
          <th>Username</th><th>NAS</th><th>IP</th>
          <th>  Download</th><th>  Upload</th><th>Duration</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <For each={sessions()}>
          {(session) => (
            <tr>
              <td>{session.username}</td>
              <td>{session.nasIp}</td>
              <td>{session.framedIp}</td>
              <td>{formatBytes(session.inputBytes)}</td>
              <td>{formatBytes(session.outputBytes)}</td>
              <td>{formatDuration(session.startedAt)}</td>
              <td><DisconnectButton sessionId={session.sessionId} /></td>
            </tr>
          )}
        </For>
      </tbody>
    </table>
  );
}
```

### GIS Map Component (Leaflet)

```tsx
// frontend/platform/src/components/maps/NasMap.tsx
import { onMount, createResource, createEffect } from "solid-js";
import L from "leaflet";
import { api } from "~/api";

export function NasMap(props: { tenantId: string }) {
  let mapEl!: HTMLDivElement;
  const [geoData] = createResource(
    () => props.tenantId,
    (id) => api.getGeoNasMap(id)
  );

  onMount(() => {
    const map = L.map(mapEl).setView([-2.5, 118], 5);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: " OpenStreetMap contributors"
    }).addTo(map);

    createEffect(() => {
      const data = geoData();
      if (!data) return;
      L.geoJSON(data, {
        pointToLayer: (feature, latlng) => {
          const color = feature.properties.status === "online" ? "green" : "red";
          return L.circleMarker(latlng, { color, radius: 8 });
        },
        onEachFeature: (feature, layer) => {
          layer.bindPopup(`
            <b>${feature.properties.name}</b><br/>
            Status: ${feature.properties.status}<br/>
            Sessions: ${feature.properties.active_sessions}
          `);
        }
      }).addTo(map);
    });
  });

  return <div ref={mapEl} style={{ height: "500px", width: "100%" }} />;
}
```

---

## 9. Roadmap Implementasi

### Fase 0 - Lite Mode & dalo Compatibility (Minggu 0-1)

- [ ] Profil deploy `oxion-lite` (Docker Compose, single VM)
- [ ] UI Simple Mode (menu inti: users, NAS, profiles, sessions, accounting, vouchers)
- [ ] dalo schema importer (`radcheck`, `radreply`, `radacct`, `nas`, `radusergroup`)
- [ ] Migration wizard: test connection -> field mapping -> dry-run -> apply
- [ ] Snapshot/rollback sebelum cutover
- [ ] Panduan upgrade Lite Mode -> Platform Mode tanpa reinstall

### Fase 1 - Core AAA / oxRADIUS (Minggu 1-3)

- [ ] Monorepo setup, semua gleam.toml, test harness
- [ ] `policy_types.gleam` v2 (tenant_id, fraud_score, anomaly_flags)
- [ ] `policy_engine.gleam`  evaluate_policy + semua guard + unit tests
- [ ] `api_gateway` Wisp + domain APIs  /v1/policy/authorize, /v1/policy/accounting, /health
- [ ] FreeRADIUS `rlm_rest` integration test (dev Docker)
- [ ] `cache_layer` ETS + Nebulex
- [ ] CoA idempotency guard (skip jika profile enforcement sudah aktif)
- [ ] `otp_supervisor` supervision tree

### Fase 2 - User Management & Multi-Tenant (Minggu 4-5)

- [ ] Subscriber CRUD + bulk import/export/generate
- [ ] Multi-tenant middleware (X-Tenant-Id + subdomain resolver)
- [ ] Multi-level ACL (operator roles + permissions)
- [ ] Reseller management
- [ ] Self-registration + SMS/Email OTP verification
- [ ] ZITADEL integration (JWT verify + PKCE flow)

### Fase 3 - oxBill: Billing & Voucher (Minggu 6-7)

- [ ] `billing_engine` - prepaid + postpaid
- [ ] Invoice PDF generator (Typst/wkhtmltopdf + Cloudflare R2/Backblaze)
- [ ] Payment adapter: Midtrans + Xendit
- [ ] `voucher_engine` - bulk generate, redeem, refill
- [ ] Collection policy engine (UI builder + JSON stages/actions, tanpa hardcoded day/speed)
- [ ] Policy simulator + publish workflow (draft -> simulated -> published)
- [ ] Notifikasi collection berbasis stage/template (dynamic payment link)
- [ ] Voucher PDF kartu print (5cm x 8cm)
- [ ] Auto top-up & renewal logic
- [ ] Payment webhook handlers

### Fase 4 - oxOLT: NAS & Accounting (Minggu 8-9)

- [ ] NAS CRUD + `nas_provisioner` MikroTik auto-config
- [ ] `accounting_pipeline` FUP + quota update + disconnect trigger
- [ ] TimescaleDB traffic_stats hypertable + continuous aggregate
- [ ] CoA/PoD dispatcher (RFC 5176)
- [ ] Signal monitoring SNMP poller
- [ ] Firmware OTA scheduler (MikroTik + OpenWRT)

### Fase 5 - oxCore: Orchestrator & Inventory (Minggu 10-11)

- [ ] Module `service` + `customers` + `packages` schema
- [ ] Orchestrator: ActivateService, SuspendService, TerminateService
- [ ] WorkflowJob + WorkflowStep dengan retry idempotent
- [ ] AAA Adapter formal
- [ ] OLT Adapter formal (facade di atas modul OLT yang ada)
- [ ] Odoo webhook handlers
- [ ] Service Inventory API
- [ ] Flow plugin hooks (`before_step`, `after_step`, `on_error`, `on_compensate`)

### Fase 6 - Superior Features (Minggu 12-14)

- [ ] `notification_engine`  WhatsApp + Telegram + SMS + Email + Push
- [ ] Python AI anomaly microservice + `ai_fraud_client` Gleam
- [ ] GraphQL schema + WebSocket subscriptions (NATS-backed)
- [ ] Crypto payment (NOWPayments + QRIS)
- [ ] Social login (Google/Facebook via ZITADEL)
- [ ] Hotspot 2.0 provisioning config
- [ ] PostGIS NAS location + GeoJSON API
- [ ] Plugin runner service + manifest validator + signature verification
- [ ] Tenant-scoped plugin activation + rollback controls

### Fase 7 - Reconciliation + GDPR (Minggu 15-16)

- [ ] Reconciliation scheduler (5 menit / 1 jam / 6 jam)
- [ ] Auto-heal: create reconcile_service job jika mismatch
- [ ] `audit_engine`  emit + query audit log
- [ ] GDPR export + erase + consent management
- [ ] OpenTelemetry tracing semua handler
- [ ] Prometheus metrics lengkap (semua kategori)
- [ ] Grafana dashboard template (JSON provisioning)
- [ ] Loki + Tempo integration

### Fase 8 - oxNOC + UI Dashboard (Minggu 17-20)

- [ ] TanStack Start + SolidJS setup
- [ ] connect-es + connect-query client scaffold untuk operator/internal API
- [ ] Dashboard utama (stats + live sessions WebSocket)
- [ ] Subscriber management CRUD + bulk
- [ ] Service detail page (3 dimensi state + workflow panel)
- [ ] Voucher batch + print PDF
- [ ] Billing + payment UI
- [ ] GIS map (Leaflet + NAS markers)
- [ ] Reports + ECharts
- [ ] NAS management + signal chart
- [ ] Firmware OTA UI
- [ ] Audit log viewer
- [ ] Tenant/reseller admin panel

### Fase 9 - Mobile App (Minggu 21-23)

- [ ] React Native + Expo project setup
- [ ] Dashboard screen (quota gauge + status)
- [ ] Voucher QR scanner + redeem
- [ ] Top-up screen (Midtrans + QRIS)
- [ ] Push notification (FCM + APNs)
- [ ] Profile + change password

### Fase 10 - Hardening & Produksi (Minggu 24-26)

- [ ] Helm charts semua komponen
- [ ] ArgoCD GitOps setup
- [ ] connect-beam adapter production readiness untuk typed internal/operator API
- [ ] mTLS FreeRADIUS -> oxRADIUS API
- [ ] RadSec untuk lintas-domain
- [ ] Load test: target >= 10.000 auth/s (2 node Gleam)
- [ ] Disaster recovery drill
- [ ] SLA baseline: p99 authorize < 30ms
- [ ] Security audit + penetration test
- [ ] White-label onboarding guide

---

## 10. Feature Coverage Matrix

| Fitur | RADIUSdesk | OpenWISP | DMA | daloRADIUS | **Oxion** |
|---|:-:|:-:|:-:|:-:|:-:|
| User management + bulk | Y | Y | Y | Y | Y |
| Voucher / prepaid | Y | N | Y | Y | Y |
| Lite mode panel FreeRADIUS-style | N | N | N | Y | Y |
| Billing + invoicing | N | N | Y | P | Y |
| Payment gateway | N | N | Y | N | Y |
| Multi-tenant | P | P | N | N | Y **SUPERIOR** |
| White label reseller portal | N | N | N | N | Y **SUPERIOR** |
| GraphQL + WebSocket | N | N | N | N | Y **SUPERIOR** |
| AI anomaly detection | N | N | N | N | Y **SUPERIOR** |
| WhatsApp/Telegram notif | N | N | N | N | Y **SUPERIOR** |
| Mobile app UCP | N | N | N | N | Y **SUPERIOR** |
| Zero-touch NAS provisioning | P | Y | N | N | Y **SUPERIOR** |
| Crypto payment + QRIS | N | N | N | N | Y **SUPERIOR** |
| Hotspot 2.0 / Passpoint | P | N | N | N | Y **SUPERIOR** |
| SSO SAML / OAuth2 | P | P | N | N | Y **SUPERIOR** |
| GDPR compliance tools | N | N | N | N | Y **SUPERIOR** |
| Firmware OTA scheduler | N | Y | N | N | Y **SUPERIOR** |
| GIS map | P | N | N | Y | Y |
| Prometheus + Grafana native | N | P | N | N | Y **SUPERIOR** |
| Kubernetes ready + HPA | N | P | N | N | Y **SUPERIOR** |
| ISP Orchestrator + oxCore | N | N | N | N | Y **SUPERIOR** |
| Service Inventory | N | N | N | N | Y **SUPERIOR** |
| Reconciliation engine | N | N | N | N | Y **SUPERIOR** |
| BEAM fault isolation | N | N | N | N | Y **SUPERIOR** |
| Static type safety (compile) | N | N | N | N | Y **SUPERIOR** |

Y = lengkap | P = parsial | N = tidak ada

---

_Dokumen ini adalah living specification. Platform: Oxion. Versi: 2.0._
