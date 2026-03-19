# oxOLT — OLT & Fiber Management

**Bagian dari platform:** Oxion ISP Operating Platform
**Versi:** 2.0
**Stack:** TypeScript/Node.js (existing modules) + Gleam NAS Provisioner

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](./oxion-infra-deployment-spec.md)
- [Platform Overview](./oxion-platform-overview.md)
- [Platform Services Specification](./oxion-platform-services-spec.md)
- [oxCore Spec](./oxcore-spec.md)
- [oxRADIUS Spec](./oxradius-spec.md)
- [oxBill Spec](./oxbill-spec.md)
- [oxNOC Spec](./oxnoc-spec.md)
- [Brand Naming](./oxion-brand-naming.md)

---

## 2. Ringkasan

oxOLT adalah modul manajemen perangkat OLT (Optical Line Terminal) dan fiber optik dari platform Oxion. Mengelola seluruh lifecycle ONU — dari auto-discovery, konfigurasi, monitoring sinyal, hingga deprovisioning — dengan dukungan multi-vendor dan integrasi penuh ke oxCore sebagai executor.

---

## 3. Arsitektur

```
oxCore (Orchestrator)
    ↓ OLT Adapter commands
oxOLT
  ├── ONU Lifecycle Manager
  ├── VLAN / Profile Manager
  ├── SNMP Worker
  ├── Remote Access (Telnet/SSH)
  ├── Scheduler
  └── Firmware OTA

    ↓ vendor protocols
OLT Devices
  ├── Huawei (MA5600T, MA5800)
  ├── ZTE (C300, C600)
  └── DOCSIS CMTS
```

---

## 4. Modul

### olt (domain utama)
- `_type` — manajemen tipe/model OLT
- `_core` — core logic OLT lintas fitur
- `_core/remote` — komunikasi remote ke perangkat OLT
- `_service` — service umum domain OLT
- `_service/attributes` — pengelolaan atribut OLT
- `_service/archive` — arsip data OLT
- `_service/check_power_port` — validasi power port
- `_service/uncfg_autofind` — autofind port belum terkonfigurasi
- `_service/clients_zte` — operasi spesifik ZTE
- `_service/clients_huawei` — operasi spesifik Huawei
- `_service/temperature` — monitoring temperatur
- `_service/all_clients` — agregasi lintas vendor
- `_scheduler` — penjadwalan job periodik
- `traffic_table` — pengelolaan traffic table
- `service_profile` — manajemen service profile
- `line_profile` — manajemen line profile
- `line_profile/gemport` — konfigurasi GEMPORT
- `line_profile/tcont` — konfigurasi T-CONT
- `vlan` — manajemen VLAN
- `lacp` — konfigurasi LACP

### onu (domain ONU)
- `power-n-status` — monitoring daya dan status
- `_type` — manajemen tipe/model ONU
- `configured` — ONU yang sudah terkonfigurasi
- `conflict` — deteksi dan penanganan konflik
- `unconfigured-client` — data unconfigured ONU (client side)
- `uncofigure` — pengelolaan ONU belum terkonfigurasi
- `inventory` — inventaris perangkat ONU
- `inv-config` — inventaris konfigurasi ONU

### snmp
- `infrastructure` — worker/queue SNMP
- `infrastructure/snmp-worker` — worker konsumsi job SNMP
- `_service` — normalisasi dan pemetaan data SNMP
- `_service/parser` — parsing payload SNMP
- `_service/remote` — interaksi remote ke perangkat

### remote-access
- `infrastructure/telnet-worker` — eksekusi command asinkron
- `effect` — implementasi Effect untuk sesi remote
- `promise` — implementasi Promise untuk koneksi remote
- `template` — template command network
- `types` — definisi tipe domain remote-access

### nas_provisioner (Gleam)
```gleam
pub type NasDevice {
  NasDevice(
    id: String,
    tenant_id: String,
    name: String,
    ip_address: String,
    nas_type: NasType,
    shared_secret: String,
    location: Option(GeoPoint),
    firmware_version: Option(String),
    status: NasStatus,
    management_protocol: ManagementProtocol,
    signal_monitoring: Bool,
  )
}

pub type NasType {
  MikroTik | CiscoIOS | PfSense | OpenWRT
  Huawei | ZTE | DOCSIS_CMTS | Generic
}

pub type ManagementProtocol {
  MikroTikAPI(port: Int)
  SSH
  SNMP(version: SnmpVersion, community: String)
  RestAPI(base_url: String)
  NETCONF
}
```

---

## 5. ONU Lifecycle

### State Machine

```
unregistered
    ↓ autofind / discovery
unconfigured
    ↓ provision (dari oxCore)
configured (active)
    ↓ deprovision / isolate
suspended / removed
```

### Provision Flow (dipanggil oxCore)

```
1. validate_attachment (OLT online, port tersedia)
2. create_onu_entry (pada OLT via remote command)
3. bind_service_profile
4. bind_line_profile
5. assign_vlan + gemport + tcont
6. create_service_port
7. verify_onu_online
8. update_provision_status → "provisioned"
```

### Deprovision Flow

```
1. remove_service_port
2. remove_onu_config
3. release_resources (VLAN, port)
4. update_provision_status → "removed"
```

---

## 6. Konfigurasi Profile

### Line Profile

```json
{
  "name": "LP_50M_BUSINESS",
  "gemport": {
    "id": 1,
    "traffic_table": "TT_50M_DOWN",
    "encryption": true
  },
  "tcont": {
    "id": 1,
    "dba_profile": "DBA_50M"
  }
}
```

### Service Profile

```json
{
  "name": "SP_50M_BUSINESS",
  "mapping_mode": "vlan",
  "vlan_id": 1203,
  "priority": 0
}
```

---

## 7. SNMP Monitoring

Data yang dikumpulkan per ONU:
- Rx optical power (dBm)
- Tx optical power (dBm)
- SNR (dB)
- BIP error count
- ONU status (online/offline/LOS/LOSi)
- Temperature OLT

```sql
-- TimescaleDB hypertable
CREATE TABLE signal_samples (
  time       TIMESTAMPTZ NOT NULL,
  nas_id     UUID NOT NULL,
  onu_id     TEXT NOT NULL,
  interface  TEXT,
  signal_dbm FLOAT,
  noise_dbm  FLOAT,
  snr_db     FLOAT,
  rx_power   FLOAT,
  tx_power   FLOAT,
  status     TEXT
);
SELECT create_hypertable('signal_samples', 'time');
```

---

## 8. Firmware OTA

```gleam
pub type FirmwareUpgrade {
  FirmwareUpgrade(
    id: String,
    nas_id: String,
    current_version: String,
    target_version: String,
    firmware_url: String,        // Cloudflare R2 / Backblaze URL
    scheduled_at: DateTime,
    status: UpgradeStatus,
    pre_check: Bool,
    rollback_on_fail: Bool,
  )
}

pub type UpgradeStatus {
  Scheduled | InProgress | Completed
  Failed(reason: String) | RolledBack
}
```

### Workflow OTA

```
1. Cek firmware terbaru vs versi aktif
2. Jadwalkan dalam maintenance window
3. Backup config NAS
4. Upload firmware ke perangkat
5. Trigger reboot
6. Monitor status (ping + SNMP)
7. Verifikasi versi baru setelah boot
8. Rollback otomatis jika gagal
9. Notify admin via oxNOC
```

---

## 9. Hotspot 2.0 & Roaming

Support 802.11r/k/v untuk enterprise deployment:
- Fast BSS Transition (802.11r)
- Neighbor Reports (802.11k)
- BSS Transition Management (802.11v)
- Passpoint R2 / ANQP
- NAI Realm configuration
- Roaming Consortium OI

---

## 10. Zero-Touch Provisioning

Auto-discovery perangkat baru:

```gleam
// 1. mDNS scanner
pub fn scan_mdns(subnet: String) -> List(DiscoveredDevice)

// 2. SNMP walker
pub fn walk_snmp(ip: String, community: String) -> Result(SnmpData, SnmpError)

// 3. LLDP listener (pasif)
pub fn start_lldp_listener(interface: String) -> Subject(LldpNeighbor)
```

---

## 11. API Endpoints

```
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

GET    /v1/onu
GET    /v1/onu/:id
GET    /v1/onu/unconfigured
POST   /v1/onu/:id/configure
POST   /v1/onu/:id/reset
DELETE /v1/onu/:id

GET    /v1/olt/:id/line-profiles
POST   /v1/olt/:id/line-profiles
GET    /v1/olt/:id/service-profiles
POST   /v1/olt/:id/service-profiles
GET    /v1/olt/:id/vlan

GET    /v1/firmware
POST   /v1/firmware
GET    /v1/firmware/upgrades
POST   /v1/firmware/upgrades/:id/schedule

GET    /v1/gis/nas           (GeoJSON FeatureCollection)
GET    /v1/gis/coverage
```

---

## 12. Database Schema

```sql
CREATE TABLE nas_devices (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID REFERENCES tenants(id) NOT NULL,
  name                TEXT NOT NULL,
  ip_address          INET NOT NULL,
  nas_type            TEXT NOT NULL,
  shared_secret       TEXT NOT NULL,
  management_protocol JSONB DEFAULT '{}',
  management_creds    JSONB DEFAULT '{}',   -- AES-256-GCM encrypted
  location            GEOMETRY(Point, 4326),
  location_name       TEXT,
  firmware_version    TEXT,
  last_seen           TIMESTAMPTZ,
  status              TEXT DEFAULT 'unknown',
  signal_monitoring   BOOLEAN DEFAULT false,
  hotspot_config      JSONB DEFAULT '{}',
  hotspot2_config     JSONB DEFAULT '{}',
  active              BOOLEAN DEFAULT true,
  UNIQUE(tenant_id, ip_address)
);
CREATE INDEX ON nas_devices USING GIST(location);

CREATE TABLE network_attachments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id       UUID NOT NULL UNIQUE,
  olt_id           UUID REFERENCES nas_devices(id),
  olt_vendor       TEXT,
  pon_fsp          TEXT,        -- 0/1/3 format
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
```

---

## 13. Prometheus Metrics

```
oxolt_onu_total{tenant_id, status}
oxolt_onu_signal_dbm{olt_id, onu_id}
oxolt_provision_success_total{vendor}
oxolt_provision_fail_total{vendor}
oxolt_nas_online_total{tenant_id}
oxolt_nas_offline_total{tenant_id}
oxolt_firmware_upgrade_total{vendor, status}
oxolt_snmp_poll_duration_ms{olt_id}
```
