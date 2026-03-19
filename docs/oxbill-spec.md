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
invoice.overdue       → "Tagihan jatuh tempo, layanan akan diputus"
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
```

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

# Reseller
GET    /v1/resellers
POST   /v1/resellers
GET    /v1/resellers/:id
PUT    /v1/resellers/:id
GET    /v1/resellers/:id/stats
GET    /v1/resellers/:id/commissions
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
```

---

## 14. Keamanan

- Webhook payload diverifikasi via HMAC signature per provider
- Payment token tersimpan sebagai tokenized reference — bukan raw card number
- PDF invoice disimpan di Cloudflare R2 / Backblaze dengan signed URL (TTL 1 jam)
- Semua transaksi masuk audit log oxNOC
