# Oxion Plugin Examples (Dengan Komentar)

## 1. Dokumen Terkait

- [Plugin Architecture](oxion-plugin-architecture.md)
- [Platform Services Specification](../architecture/oxion-platform-services-spec.md)
- [Master Arsitektur & Deployment](../architecture/oxion-infra-deployment-spec.md)
- [Plugin Manifest Schema](plugin-manifest.schema.json)

---

## 2. Contoh Manifest Plugin (Flow)

```jsonc
{
  // Format id dibikin namespace-like supaya tidak tabrakan antar vendor/tenant
  "id": "com.oxion.plugin.custom-approval",

  // Nama plugin yang tampil di UI admin
  "name": "Custom Approval Flow",

  // Semantic versioning agar upgrade/rollback terkontrol
  "version": "1.2.0",

  // Versi kontrak plugin runner Oxion
  "api_version": "v1",

  // Runtime plugin v1 dibatasi: typescript | python | elixir
  "runtime": {
    "language": "typescript",
    "version": "5.x"
  },

  // Jenis plugin menentukan hook mana yang valid
  "type": "flow",

  // Function/module entrypoint dari plugin package
  "entrypoint": "main",

  // Hook yang dipakai plugin ini
  "hooks": ["before_step", "after_step", "on_error"],

  // Least-privilege: kasih izin secukupnya saja
  "permissions": ["read:service", "write:workflow", "emit:event"],

  // Aktivasi plugin level tenant (bukan global)
  "tenant_scope": "tenant",

  // Skema config plugin, dipakai untuk validasi input dari UI/API
  "config_schema": {
    "type": "object",
    "properties": {
      "max_auto_approve": { "type": "number", "minimum": 0 },
      "required_tags": {
        "type": "array",
        "items": { "type": "string" }
      }
    },
    "required": ["max_auto_approve"]
  }
}
```

---

## 3. Contoh Flow Plugin (before_step)

Contoh berikut menunjukkan plugin approval sederhana.

```ts
// src/main.ts

type Decision = "allow" | "deny" | "require_manual_approval";

interface HookPayload {
  tenant_id: string;
  workflow: {
    job_id: string;
    step: string;
    payload: {
      monthly_fee?: number;
      tags?: string[];
    };
  };
  config: {
    max_auto_approve: number;
    required_tags?: string[];
  };
}

interface HookResult {
  decision: Decision;
  reason: string;
  patch?: Record<string, unknown>;
}

export async function before_step(input: HookPayload): Promise<HookResult> {
  // Hanya intersep step tertentu. Step lain lewat normal.
  if (input.workflow.step !== "activate_service") {
    return { decision: "allow", reason: "step_not_targeted" };
  }

  const fee = input.workflow.payload.monthly_fee ?? 0;
  const requiredTags = input.config.required_tags ?? [];
  const actualTags = input.workflow.payload.tags ?? [];

  // Validasi tag wajib untuk SOP perusahaan tertentu
  const missingTag = requiredTags.find((tag) => !actualTags.includes(tag));
  if (missingTag) {
    return {
      decision: "require_manual_approval",
      reason: `missing_required_tag:${missingTag}`
    };
  }

  // Auto-approve jika fee tidak melewati limit perusahaan
  if (fee <= input.config.max_auto_approve) {
    return {
      decision: "allow",
      reason: "within_auto_approve_limit",
      // patch opsional untuk menambah metadata pada workflow context
      patch: {
        plugin_note: "Approved by custom-approval plugin"
      }
    };
  }

  // Di atas threshold, minta approval manual
  return {
    decision: "require_manual_approval",
    reason: "fee_above_threshold"
  };
}
```

---

## 4. Contoh Policy Plugin (pre_authorize)

Contoh rule custom: deny akses jika auth terjadi di jam yang tidak diizinkan tenant.

```ts
type AuthInput = {
  tenant_id: string;
  subscriber: { id: string; username: string };
  request: { timestamp_utc: string };
  config: { allowed_hours_utc: number[] };
};

type AuthDecision = {
  decision: "allow" | "deny";
  reason: string;
};

export async function pre_authorize(input: AuthInput): Promise<AuthDecision> {
  const hour = new Date(input.request.timestamp_utc).getUTCHours();

  // Jika jam sekarang ada di daftar allowed, izinkan
  if (input.config.allowed_hours_utc.includes(hour)) {
    return { decision: "allow", reason: "within_allowed_hours" };
  }

  // Jika tidak, tolak dengan reason yang jelas untuk audit
  return { decision: "deny", reason: "outside_allowed_hours" };
}
```

---

## 5. Contoh Aktivasi Plugin per Tenant

```http
POST /v1/plugins/com.oxion.plugin.custom-approval/enable?scope=tenant&tenant_id=tnt_001
Content-Type: application/json

{
  "config": {
    "max_auto_approve": 350000,
    "required_tags": ["verified_ktp", "signed_contract"]
  }
}
```

Komentar:

- Konfigurasi ini hanya berlaku untuk tenant `tnt_001`.
- Tenant lain bisa punya threshold dan aturan tag yang berbeda.

---

## 6. Contoh Billing Plugin (commission_rule, reseller bertingkat)

Contoh ini membagi komisi invoice ke beberapa level reseller berdasarkan urutan chain.

```ts
type Money = number;

type ResellerNode = {
  reseller_id: string;
  level: number; // level 1 = reseller terdekat dengan subscriber
  commission_pct: number; // persen komisi per level (mis. 12.5)
  max_commission?: Money; // opsional cap komisi per invoice
};

type CommissionInput = {
  tenant_id: string;
  invoice: {
    invoice_id: string;
    subtotal: Money;
    tax: Money;
    total_paid: Money;
    status: "paid" | "pending" | "failed";
  };
  reseller_chain: ResellerNode[];
  config: {
    // Jika true, basis komisi pakai subtotal (tanpa pajak)
    commission_from_subtotal: boolean;
    // Batas total komisi seluruh chain agar margin aman
    total_commission_cap_pct: number;
  };
};

type CommissionEntry = {
  reseller_id: string;
  level: number;
  amount: Money;
  reason: string;
};

type CommissionResult = {
  decision: "apply" | "skip";
  entries: CommissionEntry[];
  platform_net: Money;
  reason: string;
};

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

export async function commission_rule(input: CommissionInput): Promise<CommissionResult> {
  // Komisi hanya dihitung untuk invoice yang benar-benar paid
  if (input.invoice.status !== "paid") {
    return { decision: "skip", entries: [], platform_net: 0, reason: "invoice_not_paid" };
  }

  const base = input.config.commission_from_subtotal
    ? input.invoice.subtotal
    : input.invoice.total_paid;

  // Cap total komisi global untuk proteksi margin
  const chainCap = (base * input.config.total_commission_cap_pct) / 100;

  let distributed = 0;
  const entries: CommissionEntry[] = [];

  for (const node of input.reseller_chain) {
    const raw = (base * node.commission_pct) / 100;
    const cappedByNode = node.max_commission == null ? raw : Math.min(raw, node.max_commission);

    // Sisa budget komisi chain
    const remaining = Math.max(chainCap - distributed, 0);
    const finalAmount = round2(Math.min(cappedByNode, remaining));

    if (finalAmount <= 0) {
      continue;
    }

    distributed = round2(distributed + finalAmount);
    entries.push({
      reseller_id: node.reseller_id,
      level: node.level,
      amount: finalAmount,
      reason: "level_commission_applied"
    });
  }

  // Nilai bersih platform setelah komisi reseller
  const platformNet = round2(base - distributed);

  return {
    decision: "apply",
    entries,
    platform_net: platformNet,
    reason: "commission_calculated"
  };
}
```

Catatan:

- `reseller_chain` bisa berisi level 1, 2, 3, dst sesuai struktur mitra.
- Ada 2 lapis proteksi: `max_commission` per level + `total_commission_cap_pct` per invoice.

---

## 7. Contoh Integration Plugin (inbound_webhook_adapter untuk ERP)

Contoh ini menerima webhook ERP, verifikasi signature, lalu mapping ke event internal Oxion.

```ts
import crypto from "node:crypto";

type ErpWebhookInput = {
  tenant_id: string;
  headers: Record<string, string | undefined>;
  raw_body: string;
  body: {
    event: "invoice.paid" | "subscription.suspended" | "subscription.terminated";
    customer_id: string;
    service_id: string;
    invoice_id?: string;
    paid_amount?: number;
    occurred_at: string;
  };
  config: {
    shared_secret: string;
    source_name: "odoo" | "custom_erp";
  };
};

type AdapterResult = {
  decision: "accepted" | "rejected";
  reason: string;
  emit?: {
    topic: string;
    payload: Record<string, unknown>;
  };
};

function signHmacSha256(secret: string, raw: string): string {
  return crypto.createHmac("sha256", secret).update(raw).digest("hex");
}

export async function inbound_webhook_adapter(input: ErpWebhookInput): Promise<AdapterResult> {
  const signature = input.headers["x-erp-signature"];
  if (!signature) {
    return { decision: "rejected", reason: "missing_signature" };
  }

  // Verifikasi integritas payload webhook
  const expected = signHmacSha256(input.config.shared_secret, input.raw_body);
  if (signature !== expected) {
    return { decision: "rejected", reason: "invalid_signature" };
  }

  // Mapping event ERP -> event internal Oxion
  switch (input.body.event) {
    case "invoice.paid":
      return {
        decision: "accepted",
        reason: "mapped_invoice_paid",
        emit: {
          topic: `oxion.billing.invoice_paid.${input.tenant_id}`,
          payload: {
            tenant_id: input.tenant_id,
            service_id: input.body.service_id,
            invoice_id: input.body.invoice_id,
            paid_amount: input.body.paid_amount,
            occurred_at: input.body.occurred_at,
            source: input.config.source_name
          }
        }
      };

    case "subscription.suspended":
      return {
        decision: "accepted",
        reason: "mapped_suspend",
        emit: {
          topic: `oxion.core.service_suspend.${input.tenant_id}`,
          payload: {
            tenant_id: input.tenant_id,
            service_id: input.body.service_id,
            occurred_at: input.body.occurred_at,
            source: input.config.source_name
          }
        }
      };

    case "subscription.terminated":
      return {
        decision: "accepted",
        reason: "mapped_terminate",
        emit: {
          topic: `oxion.core.service_terminate.${input.tenant_id}`,
          payload: {
            tenant_id: input.tenant_id,
            service_id: input.body.service_id,
            occurred_at: input.body.occurred_at,
            source: input.config.source_name
          }
        }
      };

    default:
      return { decision: "rejected", reason: "unsupported_event" };
  }
}
```

Catatan:

- Semua reject harus punya `reason` yang eksplisit untuk audit.
- `emit.topic` dibuat tenant-scoped supaya isolasi event tetap terjaga.

---

## 8. Template Starter Folder Plugin

Template siap pakai tersedia di folder:

- `plugin-starter/README.md`
- `plugin-starter/ts/manifest.json`
- `plugin-starter/ts/src/main.ts`
- `plugin-starter/ts/test/main.test.ts`
- `plugin-starter/python/manifest.json`
- `plugin-starter/python/src/main.py`
- `plugin-starter/python/test/test_main.py`
- `plugin-starter/elixir/manifest.json`
- `plugin-starter/elixir/lib/main.ex`
- `plugin-starter/elixir/test/main_test.exs`

Template ini sengaja minimal agar tim bisa clone cepat untuk membuat plugin baru.

---

## 9. Checklist Aman Saat Membuat Plugin

- Selalu gunakan permission minimal (least privilege).
- Pastikan setiap `deny`/`manual_approval` punya `reason` yang eksplisit.
- Tangani error plugin dengan fallback aman (default policy core).
- Simpan perubahan perilaku besar di changelog plugin.
- Uji plugin di staging sebelum enable production.
