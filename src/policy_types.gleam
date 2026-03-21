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

pub type Condition {
  All(List(Condition))
  Any(List(Condition))
  Rule(field: Field, op: Operator, value: Value, enabled: Bool)
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
