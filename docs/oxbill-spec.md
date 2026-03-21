# oxBill — Billing & Payment

**Bagian dari platform:** Oxion ISP Operating Platform
**Versi:** 2.0
**Stack:** Gleam (billing engine) + TypeScript (UI)

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](./oxion-infra-deployment-spec.md)
- [Platform Overview](./oxion-platform-overview.md)
- [Platform Services Specification](./oxion-platform-services-spec.md)
- [oxCore Spec](./oxcore-spec.md)
- [oxRADIUS Spec](./oxradius-spec.md)
- [oxOLT Spec](./oxolt-spec.md)
- [oxNOC Spec](./oxnoc-spec.md)
- [Brand Naming](./oxion-brand-naming.md)
- [Collection Policy Schema](./collection-policy.schema.json)
- [Collection Policy EBNF](./collection-policy-ebnf.md)
- [Collection Policy Contract Matrix](./collection-policy-contract-matrix.md)

---

## 2. Ringkasan

oxBill menangani seluruh siklus keuangan platform Oxion — dari pembuatan invoice otomatis, manajemen voucher dan kartu prepaid, integrasi payment gateway lokal dan internasional, hingga notifikasi pembayaran kepada pelanggan.

---

## 3. Arsitektur

```
oxCore (trigger billing events)
    ↓
oxBill
  ├── Billing Engine        (prepaid / postpaid)
  ├── Invoice Generator     (PDF via Typst/wkhtmltopdf)
  ├── Voucher Engine        (generate, redeem, refill)
  ├── Payment Adapters      (Midtrans, Xendit, Stripe, Crypto)
  ├── Auto Top-up           (renewal otomatis)
  └── Notification          (emit ke oxNOC notification engine)

    ↓ webhook callbacks
Payment Gateways
  ├── Midtrans (VA, QRIS, e-wallet)
  ├── Xendit (GoPay, OVO, DANA)
  ├── Stripe (international)
  └── NOWPayments (USDT, BTC, ETH)
```

### Dalo-Inspired Operator Layer (Adopsi Bernilai)

Oxion mengadopsi hal paling bernilai dari daloRADIUS di sisi operasional, tanpa mengorbankan prinsip platform-grade (policy-driven, event-driven, CoA-aware).

Submodule adopsi:

- `billing_plan_registry` untuk operator CRUD facade plan.
- `rate_catalog` untuk tarif versioned + effective date.
- `billing_history_query` untuk filter/query history operasional.
- `pos_counter` untuk pembayaran manual di loket/kasir.
- `payment_type_policy` untuk kontrol metode pembayaran per tenant/reseller.

Guardrails platform-grade:

- UI CRUD hanya facade; eksekusi domain tetap via command/event.
- Tidak ada hardcoded business rule di handler UI.
- Event enforcement tetap melewati `oxCore` -> `oxRADIUS`.
- Semua mutasi penting masuk audit trail.

Event minimum:

- `billing.plan.created|updated|archived`
- `billing.rate_catalog.published`
- `billing.payment.manual_recorded`
- `billing.payment_type_policy.updated`
- `billing.history.query_executed`

---

## 4. Billing Engine

### Tipe Billing

```gleam
pub type BillingPlan {
  Prepaid(
    package_id: String,
    validity_days: Int,
    price: Money,
    auto_renew: Bool,
  )
  Postpaid(
    package_id: String,
    billing_cycle: BillingCycle,
    price: Money,
    overage_rate: Option(Money),
  )
}

pub type BillingCycle {
  Monthly | Weekly | Daily | Custom(days: Int)
}

pub type Money {
  Money(amount: Int, currency: String)  // dalam sen
}

pub type CollectionLifecyclePolicy {
  CollectionLifecyclePolicy(
    id: String,
    tenant_id: String,
    name: String,

    // Grace period global, bisa dioverride per stage
    grace_days: Int,

    // Rule engine tanpa hardcoded day/speed di core
    stages: List(CollectionStage),

    // timezone evaluasi harian per tenant
    timezone: String,
  )
}

pub type CollectionStage {
  CollectionStage(
    id: String,
    priority: Int,
    when: CollectionCondition,
    actions: List(CollectionAction),
    notification_template: Option(String),
  )
}

pub type CollectionCondition {
  All(List(CollectionCondition))
  Any(List(CollectionCondition))
  Rule(field: String, op: String, value: Dynamic)
}

pub type CollectionAction {
  ApplyBandwidthProfile(profile_id: String)
  SuspendService(reason: String)
  RestoreService
  SendNotification(template_id: String, include_payment_link: Bool)
  EmitEvent(topic: String)
  SetOperationalState(state: String)
  RunPluginHook(plugin_id: String, hook: String, payload: Dynamic)
}
```

### Contoh Policy (UI Policy Builder)

Policy disusun dari UI builder dan disimpan sebagai JSON. Core tidak menanam angka hari atau speed secara hardcoded.

Kontrak JSON policy builder ada di: `./collection-policy.schema.json`.

```json
{
  "name": "Collection Default Tenant A",
  "grace_days": 0,
  "timezone": "Asia/Jakarta",
  "stages": [
    {
      "id": "soft_throttle",
      "priority": 10,
      "when": {
        "operator": "all",
        "conditions": [
          { "field": "days_past_due", "op": "gte", "value": 6 },
          { "field": "days_past_due", "op": "lte", "value": 20 }
        ]
      },
      "actions": [
        { "type": "apply_bandwidth_profile", "profile_id": "bw_4mbps" },
        { "type": "send_notification", "template_id": "collection.soft_throttle", "include_payment_link": true }
      ]
    },
    {
      "id": "hard_suspend",
      "priority": 20,
      "when": {
        "field": "days_past_due",
        "op": "gte",
        "value": 21
      },
      "actions": [
        { "type": "suspend_service", "reason": "overdue_collection" },
        { "type": "send_notification", "template_id": "collection.hard_suspend", "include_payment_link": true }
      ]
    }
  ]
}
```

---

## 5. Invoice

### Data Model

```gleam
pub type Invoice {
  Invoice(
    id: String,
    tenant_id: String,
    subscriber_id: String,
    reseller_id: Option(String),
    invoice_number: String,
    period_start: Date,
    period_end: Date,
    line_items: List(InvoiceLineItem),
    subtotal: Money,
    tax: Money,
    total: Money,
    status: InvoiceStatus,
    payment_method: Option(String),
    paid_at: Option(DateTime),
    pdf_url: Option(String),     // Cloudflare R2 / Backblaze URL
    due_date: Date,
  )
}

pub type InvoiceStatus {
  Draft | Sent | Paid | Overdue | Cancelled
}
```

### PDF Generator

```gleam
// Template Typst/wkhtmltopdf → PDF → Cloudflare R2 / Backblaze
pub fn generate_pdf(invoice: Invoice, template: String)
  -> Result(BitArray, PdfError)

pub fn store_and_get_url(pdf: BitArray, invoice_id: String, ctx: Context)
  -> Result(String, StorageError)
```

### Auto-Generate Invoice

```
Setiap tanggal 1 (scheduler oxBill):
  1. Ambil semua subscriber postpaid aktif
  2. Generate invoice periode bulan berjalan
  3. Hitung usage (dari traffic_stats oxRADIUS)
  4. Generate PDF → upload ke Cloudflare R2 / Backblaze
  5. Kirim invoice via email + WhatsApp
  6. Emit event ke Odoo (optional sync)
```

---

## 6. Voucher System

### Voucher

```gleam
pub type Voucher {
  Voucher(
    id: String,
    tenant_id: String,
    code: String,              // ABCD-1234
    qr_data: String,
    package_id: String,
    batch_id: String,
    reseller_id: Option(String),
    price: Money,
    valid_for_hours: Int,
    max_uses: Int,
    current_uses: Int,
    status: VoucherStatus,
    expires_at: Option(DateTime),
    activated_by: Option(String),
  )
}

pub type VoucherStatus {
  Active | Used | Expired | Revoked
}
```

### Voucher Batch

```gleam
pub type VoucherBatch {
  VoucherBatch(
    id: String,
    tenant_id: String,
    name: String,
    package_id: String,
    count: Int,
    price: Money,
    valid_for_hours: Int,
    expires_after_days: Int,
    pdf_url: Option(String),   // kartu print 5cm×8cm
  )
}
```

### Redeem Flow

```
1. Validasi kode voucher (format, status, expiry)
2. Cek paket yang terikat
3. Aktifkan subscriber:
   - Set/extend quota
   - Set/extend account_expiry
4. Invalidate cache oxRADIUS
5. Update voucher status → Used
6. Emit event aktivasi ke oxCore
7. Notify subscriber (WhatsApp/push)
```

### Refill Card

```gleam
pub type RefillCard {
  RefillCard(
    id: String,
    code: String,
    quota_gb: Float,     // tambah quota (bukan ganti paket)
    valid_days: Int,     // perpanjang expiry
    price: Money,
    status: VoucherStatus,
  )
}
```

---

## 7. Payment Gateways

### Midtrans (Indonesia)

```gleam
pub type MidtransMethod {
  VirtualAccount(bank: String)  // BCA, BNI, BRI, Mandiri, Permata
  QRIS
  GoPay
  ShopeePay
}
```

### Xendit (Indonesia)

```gleam
pub type XenditMethod {
  EWallet(provider: EWalletProvider)
  VirtualAccount(bank: String)
  QRIS
}

pub type EWalletProvider {
  GoPay | OVO | DANA | LinkAja | ShopeePay
}
```

### Stripe (International)

```gleam
// Credit card, Apple Pay, Google Pay
pub type StripeMethod {
  Card | ApplePay | GooglePay | SEPA | iDEAL
}
```

### NOWPayments (Crypto)

```gleam
pub type CryptoCoin {
  USDT | BTC | ETH | BNB | SOL | MATIC
}

pub fn create_crypto_payment(
  invoice: Invoice,
  coin: CryptoCoin,
  config: CryptoPaymentConfig,
) -> Result(CryptoPaymentInitiated, PaymentError)
```

### Payment Flow

```
1. Subscriber pilih metode pembayaran
2. oxBill create payment request ke gateway
3. Gateway return payment_url / VA number / QR
4. Subscriber bayar
5. Gateway kirim webhook ke oxBill
6. oxBill verifikasi webhook signature
7. Update invoice status → Paid
8. Emit event ke oxCore: payment_received
9. oxCore trigger ActivateService / unsuspend
10. Notify subscriber: "Pembayaran berhasil, layanan aktif"
```

### Overdue Enforcement Flow (Collection Lifecycle)

```text
Scheduler harian (00:15 timezone tenant):
  1. Ambil invoice postpaid status Sent/Overdue dan belum Paid
  2. Hitung days_past_due = (today - due_date)
  3. Load policy tenant dari UI Policy Builder
  4. Evaluasi stage berdasarkan `when` AST + priority
  5. Eksekusi action stage terpilih (apply profile/suspend/restore/notif/emit/set state/plugin hook)
  6. Simpan jejak eksekusi terakhir agar idempotent
```

### Recovery & Conflict Resolution

Jika ada lebih dari satu invoice overdue aktif pada subscriber yang sama, aturan precedence wajib:

1. Hitung `days_past_due` tertinggi dari seluruh invoice overdue aktif.
2. Evaluasi policy menggunakan nilai precedence tersebut (worst-case overdue).
3. Jangan restore layanan jika masih ada invoice overdue aktif lain.
4. Restore hanya dilakukan bila semua invoice yang memicu enforcement sudah `paid/cancelled`.

Kaidah ini mencegah kondisi flip-flop throttle/suspend saat pembayaran parsial beberapa invoice.

---

## 8. Auto Top-up & Renewal

```gleam
pub fn check_and_renew(subscriber: UserProfile, ctx: Context)
  -> Result(RenewalResult, RenewalError) {
  case subscriber.package.billing_plan {
    Prepaid(_, _, price, True) -> {
      case get_stored_payment_method(subscriber.id, ctx) {
        Error(_) -> Error(NoStoredPaymentMethod)
        Ok(method) ->
          billing_engine.charge(subscriber, price, method, ctx)
          |> result.map(notify_renewal_success)
      }
    }
    _ -> Ok(NoRenewalNeeded)
  }
}
```

---

## 9. Reseller & Komisi

```gleam
pub type Reseller {
  Reseller(
    id: String,
    tenant_id: String,
    name: String,
    subdomain: String,
    credit_balance: Money,
    credit_limit: Money,
    discount_percent: Float,
    commission_rate: Float,        // % dari setiap transaksi
    allowed_packages: List(String),
    max_subscribers: Option(Int),
    parent_reseller_id: Option(String),  // multi-level
    active: Bool,
  )
}
```

### Alur Komisi

```
Subscriber bayar → invoice dilunasi
  ↓
oxBill hitung komisi reseller
  (invoice.total × reseller.commission_rate)
  ↓
Credit ke reseller.credit_balance
  ↓
Reseller bisa withdraw via payment gateway
```

---

## 10. Notification Events

oxBill emit ke notification engine:

```
payment.received      → "Pembayaran Rp X berhasil diterima"
payment.failed        → "Pembayaran gagal, silakan coba lagi"
invoice.generated     → "Invoice bulan ini telah dibuat"
collection.stage.soft_throttle → "Tagihan menunggak: layanan dibatasi sesuai kebijakan"
collection.stage.hard_suspend  → "Layanan disuspend sesuai kebijakan tunggakan"
service.suspended      → "Layanan dinonaktifkan sementara sampai pembayaran diterima"
service.restored       → "Pembayaran diterima, layanan kembali normal"
voucher.redeemed      → "Voucher berhasil diaktifkan"
voucher.expiring_soon → "Voucher akan kadaluarsa dalam 24 jam"
auto_renew.success    → "Paket berhasil diperpanjang otomatis"
auto_renew.failed     → "Perpanjangan otomatis gagal, topup manual diperlukan"
quota.warning         → "Kuota tersisa 20%"
quota.exhausted       → "Kuota habis, FUP aktif"
```

---

## 11. Database Schema

```sql
CREATE TABLE invoices (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID REFERENCES tenants(id) NOT NULL,
  subscriber_id    UUID NOT NULL,
  reseller_id      UUID REFERENCES resellers(id),
  invoice_number   TEXT UNIQUE NOT NULL,
  period_start     DATE,
  period_end       DATE,
  line_items       JSONB DEFAULT '[]',
  subtotal         BIGINT NOT NULL,
  tax              BIGINT DEFAULT 0,
  total            BIGINT NOT NULL,
  currency         TEXT DEFAULT 'IDR',
  status           TEXT DEFAULT 'draft',
  payment_method   TEXT,
  payment_reference TEXT,
  paid_at          TIMESTAMPTZ,
  due_date         DATE,
  pdf_url          TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE voucher_batches (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          UUID REFERENCES tenants(id) NOT NULL,
  reseller_id        UUID REFERENCES resellers(id),
  name               TEXT NOT NULL,
  package_id         UUID NOT NULL,
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
  code            TEXT NOT NULL,
  qr_data         TEXT NOT NULL,
  package_id      UUID NOT NULL,
  price           BIGINT NOT NULL,
  valid_for_hours INT NOT NULL,
  max_uses        INT DEFAULT 1,
  current_uses    INT DEFAULT 0,
  status          TEXT DEFAULT 'active',
  activated_by    UUID,
  activated_at    TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, code)
);

CREATE TABLE payment_methods_on_file (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id  UUID NOT NULL,
  type           TEXT NOT NULL,
  provider_token TEXT NOT NULL,   -- tokenized, never raw card
  is_default     BOOLEAN DEFAULT false,
  expires_at     DATE
);

CREATE TABLE billing_plan_registry (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID REFERENCES tenants(id) NOT NULL,
  plan_code           TEXT NOT NULL,
  name                TEXT NOT NULL,
  billing_plan_json   JSONB NOT NULL,
  radius_profile_hint TEXT,
  active              BOOLEAN NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, plan_code)
);

CREATE TABLE billing_rate_catalog (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID REFERENCES tenants(id) NOT NULL,
  catalog_name     TEXT NOT NULL,
  version          INT NOT NULL,
  effective_from   TIMESTAMPTZ NOT NULL,
  effective_to     TIMESTAMPTZ,
  rates_json       JSONB NOT NULL,
  lifecycle_status TEXT NOT NULL DEFAULT 'draft',
  -- draft | simulated | published | archived
  created_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, catalog_name, version)
);

CREATE TABLE billing_pos_transactions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          UUID REFERENCES tenants(id) NOT NULL,
  subscriber_id      UUID NOT NULL,
  invoice_id         UUID REFERENCES invoices(id),
  cashier_id         UUID,
  payment_type_code  TEXT NOT NULL,
  amount             BIGINT NOT NULL,
  currency           TEXT NOT NULL DEFAULT 'IDR',
  receipt_number     TEXT NOT NULL,
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, receipt_number)
);

CREATE TABLE payment_type_policies (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID REFERENCES tenants(id) NOT NULL,
  reseller_id         UUID REFERENCES resellers(id),
  payment_type_code   TEXT NOT NULL,
  enabled             BOOLEAN NOT NULL DEFAULT true,
  constraints_json    JSONB DEFAULT '{}',
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, reseller_id, payment_type_code)
);

CREATE TABLE billing_history_index (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          UUID REFERENCES tenants(id) NOT NULL,
  subscriber_id      UUID,
  invoice_id         UUID,
  event_type         TEXT NOT NULL,
  event_ref          TEXT,
  payload            JSONB DEFAULT '{}',
  created_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE collection_policies (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id              UUID REFERENCES tenants(id) NOT NULL,
  name                   TEXT NOT NULL,
  grace_days             INT NOT NULL DEFAULT 0,
  policy_json            JSONB NOT NULL,
  policy_version         INT NOT NULL DEFAULT 1,
  lifecycle_status       TEXT NOT NULL DEFAULT 'draft',
  -- draft | simulated | published | archived
  is_active              BOOLEAN NOT NULL DEFAULT false,
  simulated_at           TIMESTAMPTZ,
  published_at           TIMESTAMPTZ,
  timezone               TEXT NOT NULL DEFAULT 'Asia/Jakarta',
  created_at             TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE collection_policies
  ADD CONSTRAINT chk_collection_policy_lifecycle
  CHECK (lifecycle_status IN ('draft', 'simulated', 'published', 'archived'));

-- Satu tenant hanya boleh punya satu policy aktif-published pada satu waktu
CREATE UNIQUE INDEX ux_collection_policy_single_active_published
  ON collection_policies(tenant_id)
  WHERE lifecycle_status = 'published' AND is_active = true;

-- Versioning policy per tenant harus unik
CREATE UNIQUE INDEX ux_collection_policy_tenant_version
  ON collection_policies(tenant_id, policy_version);

CREATE TABLE collection_enforcement_log (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            UUID REFERENCES tenants(id) NOT NULL,
  subscriber_id        UUID NOT NULL,
  invoice_id           UUID REFERENCES invoices(id) NOT NULL,
  days_past_due        INT NOT NULL,
  stage_id             TEXT,
  action               TEXT NOT NULL,
  action_payload       JSONB DEFAULT '{}',
  action_fingerprint   TEXT NOT NULL,
  executed_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, action_fingerprint)
);
```

### Policy Lifecycle State Transition Table

Invarian utama:

- Hanya policy dengan `lifecycle_status='published'` yang boleh `is_active=true`.
- Dalam satu tenant, hanya boleh ada satu policy `published + is_active=true`.

| Dari | Ke | Status | Trigger API | Catatan |
| --- | --- | --- | --- | --- |
| `draft` | `simulated` | **Allowed** | `POST /v1/collection/policies/:id/simulate` | Wajib lulus schema + semantic validation |
| `simulated` | `published` | **Allowed** | `POST /v1/collection/policies/:id/publish` | Publish membuat `published_at` |
| `published` | `archived` | **Allowed** | `POST /v1/collection/policies/:id/archive` | Policy archived tidak boleh aktif |
| `simulated` | `draft` | **Allowed** | `PUT /v1/collection/policies/:id` | Edit policy reset status ke draft |
| `draft` | `draft` | **Allowed** | `PUT /v1/collection/policies/:id` | Update konten tanpa ubah lifecycle |
| `simulated` | `simulated` | **Allowed** | `POST /v1/collection/policies/:id/simulate` | Re-simulate untuk update hasil |
| `published` | `published` | **Allowed** | `POST /v1/collection/policies/:id/activate` | Re-activate idempotent |
| `archived` | `draft` | **Forbidden** | - | Tidak boleh revive policy lama; buat versi baru |
| `archived` | `simulated` | **Forbidden** | - | Archived immutable |
| `archived` | `published` | **Forbidden** | - | Archived immutable |
| `draft` | `published` | **Forbidden** | - | Harus melewati simulate dulu |
| `published` | `draft` | **Forbidden** | - | Setelah publish, perubahan harus lewat policy version baru |
| `published` | `simulated` | **Forbidden** | - | Tidak ada downgrade; gunakan clone version |

### Aturan Aktivasi (`is_active`)

- `POST /v1/collection/policies/:id/activate` hanya valid bila policy sudah `published`.
- Saat aktivasi policy baru untuk tenant yang sama:
  1. set policy active lama (`published`) -> `is_active=false`
  2. set policy target -> `is_active=true`
  3. commit atomik dalam satu transaksi DB
- Jika langkah 1/2 gagal, transaction rollback penuh (tidak boleh ada dua active).

### Error Code Normatif (Lifecycle)

```json
{
  "code": "INVALID_POLICY_TRANSITION",
  "policy_id": "pol_123",
  "from": "draft",
  "to": "published",
  "reason": "simulate_required_before_publish"
}
```

Kode minimum:

- `INVALID_POLICY_TRANSITION`
- `POLICY_NOT_PUBLISHED`
- `ACTIVE_POLICY_CONFLICT`
- `POLICY_IMMUTABLE_ARCHIVED`

---

## 12. API Endpoints

```
# Invoice
GET    /v1/invoices
POST   /v1/invoices
GET    /v1/invoices/:id
GET    /v1/invoices/:id/pdf
POST   /v1/invoices/:id/pay
POST   /v1/invoices/:id/cancel

# Collection policy & enforcement
GET    /v1/collection/policies
POST   /v1/collection/policies
GET    /v1/collection/policies/:id
PUT    /v1/collection/policies/:id
POST   /v1/collection/policies/:id/simulate
POST   /v1/collection/policies/:id/publish
POST   /v1/collection/policies/:id/archive
POST   /v1/collection/policies/:id/activate
POST   /v1/collection/enforce/run

# Billing plan registry (operator facade)
GET    /v1/billing/plans
POST   /v1/billing/plans
GET    /v1/billing/plans/:id
PUT    /v1/billing/plans/:id
POST   /v1/billing/plans/:id/archive

# Rate catalog (versioned)
GET    /v1/billing/rate-catalogs
POST   /v1/billing/rate-catalogs
POST   /v1/billing/rate-catalogs/:id/simulate
POST   /v1/billing/rate-catalogs/:id/publish

# POS counter
GET    /v1/billing/pos/transactions
POST   /v1/billing/pos/transactions

# Payment type policy
GET    /v1/billing/payment-type-policies
PUT    /v1/billing/payment-type-policies/:id

# Billing history query
GET    /v1/billing/history

# Payment
GET    /v1/payments
POST   /v1/payments/webhook/midtrans
POST   /v1/payments/webhook/xendit
POST   /v1/payments/webhook/stripe
POST   /v1/payments/webhook/nowpayments

# Voucher
GET    /v1/voucher-batches
POST   /v1/voucher-batches
GET    /v1/voucher-batches/:id
GET    /v1/voucher-batches/:id/vouchers
GET    /v1/voucher-batches/:id/pdf
POST   /v1/vouchers/redeem
GET    /v1/vouchers/:code
DELETE /v1/vouchers/:id

# Self-service (UCP)
GET    /v1/self/invoices
POST   /v1/self/topup
POST   /v1/self/voucher/redeem
GET    /v1/self/quota

# Reseller billing view (read-only, bukan domain management reseller)
GET    /v1/billing/reseller-commissions
GET    /v1/billing/reseller-commissions/:reseller_id

# Catatan boundary domain
# Reseller management berada di oxCore/platform-services domain.
# oxBill hanya expose data komisi/faktur reseller via endpoint billing domain.
```

---

## 13. Prometheus Metrics

```
oxbill_invoice_total{tenant_id, status}
oxbill_invoice_overdue_total{tenant_id}
oxbill_payment_total{tenant_id, method, status}
oxbill_revenue_total{tenant_id, currency}
oxbill_voucher_generated_total{tenant_id}
oxbill_voucher_redeemed_total{tenant_id}
oxbill_voucher_expired_total{tenant_id}
oxbill_auto_renew_success_total{tenant_id}
oxbill_auto_renew_fail_total{tenant_id}
oxbill_collection_policy_eval_total{tenant_id, policy_id, stage_id, result}
oxbill_collection_action_total{tenant_id, stage_id, action, result}
oxbill_collection_idempotent_skip_total{tenant_id, action}
oxbill_collection_restore_total{tenant_id, result}
oxbill_collection_overdue_conflict_total{tenant_id, subscriber_id}
oxbill_plan_registry_total{tenant_id, status}
oxbill_rate_catalog_total{tenant_id, lifecycle_status}
oxbill_pos_transaction_total{tenant_id, payment_type_code}
oxbill_payment_type_policy_update_total{tenant_id}
oxbill_billing_history_query_total{tenant_id, query_type}
```

---

## 14. Keamanan

- Webhook payload diverifikasi via HMAC signature per provider
- Payment token tersimpan sebagai tokenized reference — bukan raw card number
- PDF invoice disimpan di Cloudflare R2 / Backblaze dengan signed URL (TTL 1 jam)
- Semua transaksi masuk audit log oxNOC
