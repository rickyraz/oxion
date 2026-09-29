import gleam/option

// Why: preserve schema-level metadata so core modules do not silently drop
// contract fields before validation, simulation, or dispatching.
pub type PaymentLinkMode {
  StaticPaymentLink
  SignedPaymentLink
}

pub type PolicyContextConfig {
  PolicyContextConfig(
    evaluation_time: option.Option(String),
    payment_link_mode: option.Option(PaymentLinkMode),
    payment_link_base_url: option.Option(String),
    payment_link_ttl_minutes: option.Option(Int),
  )
}

// Why: payload-bearing actions need a deterministic, testable JSON-like shape
// instead of opaque dynamic values that the current core cannot inspect.
pub type JsonValue {
  JsonNull
  JsonBool(Bool)
  JsonInt(Int)
  JsonFloat(Float)
  JsonString(String)
  JsonArray(List(JsonValue))
  JsonObject(List(#(String, JsonValue)))
}

pub type Field {
  DaysPastDue
  InvoiceStatus
  OperationalState
  BillingPlan
  TotalDueAmount
  IsPaid
}

pub type Operator {
  Eq
  Ne
  Gt
  Gte
  Lt
  Lte
  In
  NotIn
  Between
  IsTrue
  IsFalse
}

pub type Scalar {
  IntValue(Int)
  StringValue(String)
  BoolValue(Bool)
}

pub type Value {
  ScalarValue(Scalar)
  ListValue(List(Scalar))
  BetweenValue(min: Int, max: Int)
  NoValue
}

// Condition = bisa berupa kumpulan aturan AND, kumpulan aturan OR, atau satu aturan tunggal.
// Action = bisa berupa penerapan profil bandwidth, penangguhan layanan, pemulihan layanan, pengiriman notifikasi, emisi event, pengaturan status operasional, atau menjalankan plugin hook.
// Stage = terdiri dari ID, prioritas, kondisi, daftar aksi, flag untuk menghentikan evaluasi jika cocok, template notifikasi opsional, dan flag enabled.
// Policy = terdiri dari nama, deskripsi opsional, jumlah grace days, zona waktu, konfigurasi konteks opsional, dan daftar stage.
// Context = terdiri dari hari keterlambatan, status faktur, status operasional, rencana penagihan, total jumlah yang harus dibayar, dan status pembayaran.
// LifecycleStatus = bisa berupa Draft, Simulated, Published, atau Archived.
// TransitionError = error yang terjadi saat mencoba melakukan transisi lifecycle yang tidak valid, dengan informasi status asal dan tujuan.
// ActivationError = error yang terjadi saat mencoba mengaktifkan kebijakan yang tidak memenuhi prasyarat publikasi, konflik dengan kebijakan aktif lainnya, atau sudah diarsipkan dan tidak dapat diubah.
// ActivationState = kombinasi dari status lifecycle dan apakah kebijakan saat ini aktif atau tidak, untuk memastikan invariants aktivasi yang benar dalam mesin status.
// Why: modeling conditions and actions as explicit types with domain-specific fields allows the policy engine to perform validation, simulation, and execution with full visibility into the semantics of each
// rule, instead of treating them as opaque data that can lead to errors or unintended consequences at runtime. This also enables better tooling and testing around policy definitions.
pub type Condition {
  All(List(Condition)) // semua kondisi di dalam list harus benar
  Any(List(Condition)) // setidaknya satu kondisi di dalam list harus benar
  Rule(field: Field, op: Operator, value: Value, enabled: Bool) // aturan tunggal dengan field, operator, dan nilai yang ditentukan
}

pub type NotificationChannel {
  Whatsapp
  Telegram
  Sms
  Email
  Push
}

pub type Action {
  ApplyBandwidthProfile(profile_id: String)
  SuspendService(reason: String)
  RestoreService
  SendNotification(
    template_id: String,
    include_payment_link: Bool,
    channels: List(NotificationChannel),
  )
  EmitEvent(topic: String, payload: option.Option(JsonValue))
  SetOperationalState(state: String)
  RunPluginHook(
    plugin_id: String,
    hook: String,
    payload: option.Option(JsonValue),
  )
}

pub type Stage {
  Stage(
    id: String,
    priority: Int,
    condition: Condition,
    actions: List(Action),
    stop_on_match: Bool,
    notification_template: option.Option(String),
    enabled: Bool,
  )
}

pub type Policy {
  Policy(
    name: String,
    description: option.Option(String),
    grace_days: Int,
    timezone: String,
    context: option.Option(PolicyContextConfig),
    stages: List(Stage),
  )
}

pub type Context {
  Context(
    days_past_due: Int,
    invoice_status: String,
    operational_state: String,
    billing_plan: String,
    total_due_amount: Int,
    is_paid: Bool,
  )
}
