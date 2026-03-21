# oxion — Platform Services Specification

**Cakupan:** Multi-level ACL & Reseller, Multi-Tenant & White Label, Real-time GraphQL + WebSocket, Notification Engine, Mobile App UCP, SSO/SAML/OAuth2/ZITADEL, Audit Log & GDPR Compliance

## 1. Dokumen Terkait

- [Master Arsitektur & Deployment](oxion-infra-deployment-spec.md)
- [Platform Overview](oxion-platform-overview.md)
- [oxRADIUS Spec](../modules/oxradius-spec.md)
- [oxCore Spec](../modules/oxcore-spec.md)
- [oxOLT Spec](../modules/oxolt-spec.md)
- [oxBill Spec](../modules/oxbill-spec.md)
- [oxNOC Spec](../modules/oxnoc-spec.md)
- [Brand Naming](oxion-brand-naming.md)
- [Plugin Architecture](../plugins/oxion-plugin-architecture.md)
- [Plugin Examples](../plugins/oxion-plugin-examples.md)

---

## 2. Profil Operasi & Feature Flags

Oxion mendukung dua profil operasi dalam satu codebase:

- **Lite Mode**: panel operasional inti untuk skenario kecil, default menu sederhana.
- **Platform Mode**: semua fitur lanjutan aktif (multi-tenant, orchestration, observability, integrasi lanjutan).

### Flag Profil

```json
{
  "profile": "lite",
  "features": {
    "multi_tenant": false,
    "reseller": false,
    "graphql_realtime": false,
    "ai_anomaly": false,
    "gis_map": false,
    "firmware_ota": false,
    "advanced_observability": false
  }
}
```

Pada profile `platform`, seluruh flag di atas dapat diaktifkan per tenant sesuai plan.

---

## 3. Multi-level ACL & Reseller

### Operator Roles & Permissions

```gleam
// policy_types.gleam

pub type OperatorRole {
  SuperAdmin              // full access, semua tenant
  TenantAdmin             // full access dalam satu tenant
  Reseller(ResellerId)    // manage subscribers di bawahnya
  Cashier                 // billing only, no config
  HelpDesk                // read + disconnect/coa, no billing
  ReadOnly                // view only
}

pub type Permission {
  ViewSubscribers
  CreateSubscribers
  EditSubscribers
  DeleteSubscribers
  ViewBilling
  ManageBilling
  CreateVouchers
  ViewReports
  ManageNAS
  ManagePackages
  TriggerCoA
  ViewAuditLog
  ManageTenant
  ManageResellers
  ExportData
}
```

### Reseller Type

```gleam
pub type Reseller {
  Reseller(
    id: String,
    tenant_id: String,
    name: String,
    subdomain: String,              // untuk white-label
    branding: ResellerBranding,
    credit_balance: Money,
    credit_limit: Money,
    discount_percent: Float,
    allowed_packages: List(String),
    max_subscribers: Option(Int),
    parent_reseller_id: Option(String),  // multi-level reseller
    commission_rate: Float,
    active: Bool,
  )
}

pub type ResellerBranding {
  ResellerBranding(
    logo_url: Option(String),
    primary_color: String,
    secondary_color: String,
    company_name: String,
    support_email: Option(String),
    support_phone: Option(String),
    custom_domain: Option(String),
    favicon_url: Option(String),
  )
}
```

### Database Schema

```sql
CREATE TABLE operators (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID REFERENCES tenants(id) NOT NULL,
  reseller_id   UUID REFERENCES resellers(id),
  username      TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  email         TEXT,
  role          TEXT NOT NULL,
  -- superadmin | tenantadmin | reseller | cashier | helpdesk | readonly
  permissions   TEXT[] DEFAULT '{}',
  active        BOOLEAN DEFAULT true,
  last_login    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE resellers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id) NOT NULL,
  parent_id       UUID REFERENCES resellers(id),     -- multi-level
  name            TEXT NOT NULL,
  subdomain       TEXT,
  branding        JSONB DEFAULT '{}',
  credit_balance  BIGINT DEFAULT 0,                  -- dalam sen
  credit_limit    BIGINT DEFAULT 0,
  discount_pct    NUMERIC(5,2) DEFAULT 0,
  commission_rate NUMERIC(5,2) DEFAULT 0,
  active          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

### API Endpoints

```
GET  /v1/resellers
POST /v1/resellers
GET  /v1/resellers/:id
PUT  /v1/resellers/:id
GET  /v1/resellers/:id/subscribers
GET  /v1/resellers/:id/stats
GET  /v1/resellers/:id/commissions
```

---

## 4. Multi-Tenant & White Label

### Tenant Type

```gleam
pub type Tenant {
  Tenant(
    id: String,
    slug: String,                  // URL-safe identifier
    name: String,
    custom_domain: Option(String), // CNAME ke platform
    branding: TenantBranding,
    features: TenantFeatures,      // feature flags per tenant
    plan: TenantPlan,
    max_subscribers: Option(Int),
    max_nas: Option(Int),
    active: Bool,
    created_at: DateTime,
  )
}

pub type TenantFeatures {
  TenantFeatures(
    social_login: Bool,
    crypto_payment: Bool,
    ai_anomaly: Bool,
    hotspot_2: Bool,
    firmware_ota: Bool,
    whatsapp_notification: Bool,
    telegram_notification: Bool,
    gis_map: Bool,
    multi_reseller: Bool,
  )
}

pub type TenantPlan {
  Starter(max_subscribers: Int)
  Pro(max_subscribers: Int)
  Enterprise           // unlimited
  Custom(limits: TenantLimits)
}
```

### Tenant Middleware

```gleam
// middleware/tenant_middleware.gleam

pub fn resolve_tenant(
  req: Request,
  ctx: Context,
  next: fn(Request, TenantContext) -> Response,
) -> Response {
  // Resolve tenant dari:
  // 1. X-Tenant-Id header (API calls)
  // 2. Host header subdomain (reseller.domain.com)
  // 3. JWT claims (authenticated requests)
  let tenant_id = case wisp.get_header(req, "x-tenant-id") {
    Ok(id) -> Ok(id)
    Error(_) -> resolve_from_host(req, ctx)
  }

  case tenant_id {
    Error(_) -> wisp.response(400) |> with_json(error_json("tenant_not_resolved"))
    Ok(id) ->
      case cache_layer.get(TenantById(id), ctx.cache) {
        None -> wisp.response(404)
        Some(tenant) ->
          next(req, TenantContext(tenant_id: id, tenant: tenant))
      }
  }
}
```

### White Label Subdomain Resolver

```gleam
fn resolve_from_host(req: Request, ctx: Context) -> Result(String, Nil) {
  case wisp.get_header(req, "host") {
    Error(_) -> Error(Nil)
    Ok(host) -> {
      // "reseller-abc.oxion.io" → "reseller-abc"
      let slug = string.split(host, ".") |> list.first
      case slug {
        Error(_) -> Error(Nil)
        Ok(s) ->
          case cache_layer.get(TenantBySlug(s), ctx.cache) {
            None -> Error(Nil)
            Some(t) -> Ok(t.id)
          }
      }
    }
  }
}
```

### Database Schema

```sql
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

CREATE TABLE login_pages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID REFERENCES tenants(id) NOT NULL,
  reseller_id     UUID REFERENCES resellers(id),
  name            TEXT NOT NULL,
  html_template   TEXT NOT NULL,
  css_override    TEXT,
  logo_url        TEXT,
  background_url  TEXT,
  primary_color   TEXT DEFAULT '#1a73e8',
  social_buttons  TEXT[] DEFAULT '{}',
  languages       TEXT[] DEFAULT '{"id","en"}',
  is_default      BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

### Apa yang Didapat Setiap Reseller

- Subdomain sendiri (`reseller-a.oxion.io`) atau custom domain via CNAME
- Branding: logo, warna, company name
- Isolated subscriber data
- Isolated billing & invoice template
- Isolated login page untuk captive portal
- Feature flags yang dikonfigurasi per tenant

### API Endpoints

```
GET  /v1/tenants              (superadmin only)
POST /v1/tenants
GET  /v1/tenants/:id
PUT  /v1/tenants/:id

GET    /v1/login-pages
POST   /v1/login-pages
GET    /v1/login-pages/:id
PUT    /v1/login-pages/:id
DELETE /v1/login-pages/:id
```

---

## 5. Real-time GraphQL + WebSocket

### GraphQL Schema (Absinthe via Erlang Interop)

```graphql
# Schema GraphQL — oxion platform

type Query {
  subscriber(id: ID!): Subscriber
  subscribers(filter: SubscriberFilter, page: PageInput): SubscriberPage
  activeSessions(nasId: ID, tenantId: ID): [Session!]!
  stats(tenantId: ID!): DashboardStats
  invoice(id: ID!): Invoice
  vouchers(batchId: ID!): [Voucher!]!
  nasDevices(tenantId: ID!): [NasDevice!]!
  trafficReport(subscriberId: ID!, range: DateRange!): [TrafficPoint!]!
  geoNasMap(tenantId: ID!): [NasGeoPoint!]!
  service(id: ID!): Service
  services(filter: ServiceFilter): [Service!]!
  workflowJob(id: ID!): WorkflowJob
}

type Mutation {
  createSubscriber(input: CreateSubscriberInput!): Subscriber!
  updateSubscriber(id: ID!, input: UpdateSubscriberInput!): Subscriber!
  triggerCoa(subscriberId: ID!, type: CoaType!): CoaResult!
  disconnectSubscriber(subscriberId: ID!): Boolean!
  redeemVoucher(code: String!, subscriberId: ID!): VoucherRedeemResult!
  generateVoucherBatch(input: VoucherBatchInput!): VoucherBatch!
  sendNotification(input: NotificationInput!): Boolean!
  createInvoice(subscriberId: ID!): Invoice!
  triggerPayment(invoiceId: ID!, method: PaymentMethod!): PaymentInitiated!
  activateService(serviceId: ID!): WorkflowJob!
  suspendService(serviceId: ID!): WorkflowJob!
  terminateService(serviceId: ID!): WorkflowJob!
}

type Subscription {
  # Live session updates
  sessionUpdated(tenantId: ID!): Session!

  # Real-time accounting events
  accountingEvent(subscriberId: ID): AccountingEvent!

  # Anomaly alerts
  anomalyDetected(tenantId: ID!): AnomalyAlert!

  # CoA result callbacks
  coaResult(tenantId: ID!): CoaResult!

  # Payment status updates
  paymentStatusChanged(invoiceId: ID!): PaymentStatusEvent!

  # Workflow progress
  workflowStepUpdated(jobId: ID!): WorkflowStep!

  # Service state changes
  serviceStateChanged(tenantId: ID!): ServiceStateEvent!
}
```

### WebSocket Handler (Gleam)

```gleam
// api_server/src/ws_handler.gleam

pub type WsMessage {
  Subscribe(topic: String, id: String)
  Unsubscribe(topic: String, id: String)
  Event(topic: String, payload: Json)
  Ping
  Pong
}

pub type WsTopic {
  Sessions(tenant_id: String)
  AccountingEvents(subscriber_id: String)
  AnomalyAlerts(tenant_id: String)
  CoaCallbacks(tenant_id: String)
  PaymentUpdates(invoice_id: String)
  WorkflowProgress(job_id: String)
  ServiceStateChanges(tenant_id: String)
}

pub fn handle_ws(connection: WsConnection, ctx: Context) {
  receive_loop(connection, ctx, [])
}

fn receive_loop(conn: WsConnection, ctx: Context, subscriptions: List(WsTopic)) {
  case mist.receive_message(conn) {
    Ok(msg) -> {
      let #(reply, new_subs) = process_ws_message(msg, ctx, subscriptions)
      case reply {
        Some(r) -> mist.send(conn, r)
        None    -> Nil
      }
      receive_loop(conn, ctx, new_subs)
    }
    Error(_) -> {
      list.each(subscriptions, fn(sub) {
        nats_client.unsubscribe(sub, ctx.nats)
      })
    }
  }
}
```

### NATS JetStream Event Subjects

```
// oxRADIUS events
aaa.sessions.{tenant_id}
aaa.accounting.{subscriber_id}
aaa.anomaly.{tenant_id}
aaa.coa.result.{tenant_id}

// oxBill events
aaa.payment.{invoice_id}

// oxCore events
oxcore.service.state.{tenant_id}
oxcore.workflow.step.{job_id}
oxcore.reconcile.result.{tenant_id}

// oxOLT events
oxolt.onu.status.{olt_id}
oxolt.provision.result.{service_id}

// Audit
aaa.audit.{tenant_id}
```

### Endpoints

```
POST /graphql
GET  /graphql/subscriptions     (WebSocket upgrade)
```

---

## 6. Notification Engine

### Notification Events

```gleam
// apps/notification_engine/src/notification_engine.gleam

pub type NotificationEvent {
  WelcomeMessage(subscriber: UserProfile)
  QuotaWarning(subscriber: UserProfile, percent_used: Float)
  QuotaExhausted(subscriber: UserProfile)
  FupActivated(subscriber: UserProfile)
  AccountExpiringSoon(subscriber: UserProfile, days_left: Int)
  AccountExpired(subscriber: UserProfile)
  PaymentSuccess(subscriber: UserProfile, invoice: Invoice)
  PaymentFailed(subscriber: UserProfile, invoice: Invoice)
  VoucherActivated(subscriber: UserProfile, voucher: Voucher)
  AutoRenewSuccess(subscriber: UserProfile, package: ServicePackage)
  AnomalyAlert(admin_contact: Contact, result: AnomalyResult)
  ServiceActivated(subscriber: UserProfile, service_id: String)
  ServiceSuspended(subscriber: UserProfile, reason: String)
  OltOfflineAlert(admin_contact: Contact, nas: NasDevice)
  BulkMessage(recipients: List(Contact), message: String)
}

pub type NotificationChannel {
  WhatsApp
  Telegram
  SMS
  Email
  PushNotification
}

pub fn send(
  event: NotificationEvent,
  channels: List(NotificationChannel),
  config: NotificationConfig,
) -> Result(List(NotificationResult), NotificationError) {
  let template = template_renderer.resolve(event)
  channels
  |> list.map(fn(channel) {
    case channel {
      WhatsApp         -> whatsapp_channel.send(event, template, config.whatsapp)
      Telegram         -> telegram_channel.send(event, template, config.telegram)
      SMS              -> sms_channel.send(event, template, config.sms)
      Email            -> email_channel.send(event, template, config.email)
      PushNotification -> push_channel.send(event, template, config.push)
    }
  })
  |> result.all
}
```

### WhatsApp Business API Channel

```gleam
// channels/whatsapp_channel.gleam

pub type WhatsAppConfig {
  WhatsAppConfig(
    provider: WaProvider,
    api_key: String,
    from_number: String,
    template_namespace: String,
  )
}

pub type WaProvider {
  WhatsAppBusinessAPI    // Meta official
  Fonnte                 // Lokal Indonesia
  WaGateway              // Self-hosted
  Twilio
}

pub fn send(
  event: NotificationEvent,
  template: RenderedTemplate,
  config: WhatsAppConfig,
) -> Result(NotificationResult, ChannelError) {
  case config.provider {
    WhatsAppBusinessAPI -> send_via_meta(template, config)
    Fonnte              -> send_via_fonnte(template, config)
    Twilio              -> send_via_twilio(template, config)
    WaGateway           -> send_via_gateway(template, config)
  }
}
```

### Telegram Bot Channel

```gleam
// channels/telegram_channel.gleam

pub type TelegramConfig {
  TelegramConfig(
    bot_token: String,
    admin_chat_id: String,
    subscriber_link: Bool,
  )
}

pub fn send(
  event: NotificationEvent,
  template: RenderedTemplate,
  config: TelegramConfig,
) -> Result(NotificationResult, ChannelError) {
  let chat_id = resolve_chat_id(event, config)
  let payload = json.object([
    #("chat_id", json.string(chat_id)),
    #("text", json.string(template.text)),
    #("parse_mode", json.string("HTML")),
  ])
  httpc.post(
    "https://api.telegram.org/bot" <> config.bot_token <> "/sendMessage",
    payload,
  )
  |> result.map(fn(_) { NotificationResult(channel: Telegram, status: Sent) })
}
```

### Push Notification Channel

```gleam
// channels/push_channel.gleam

pub type PushToken {
  PushToken(
    subscriber_id: String,
    token: String,
    platform: PushPlatform,
    registered_at: DateTime,
  )
}

pub type PushPlatform {
  FCM    // Android
  APNs   // iOS
  Expo   // Expo push service (multiplatform)
}

pub fn send(
  event: NotificationEvent,
  template: RenderedTemplate,
  config: PushConfig,
) -> Result(NotificationResult, ChannelError) {
  // Ambil token subscriber dari DB
  // Kirim ke Expo Push API atau langsung FCM/APNs
}
```

### Notification Scheduler (Cron)

```gleam
// scheduler.gleam — job terjadwal, dijalankan dalam OTP supervisor

pub fn start_scheduler(ctx: Context) {
  // Cek expiring accounts setiap jam
  schedule(Every(Hours(1)), fn() {
    check_expiring_accounts(ctx)
  })

  // Cek quota warning setiap 15 menit
  schedule(Every(Minutes(15)), fn() {
    check_quota_warnings(ctx)
  })

  // Billing invoice generation tanggal 1 setiap bulan
  schedule(Monthly(day: 1, hour: 0), fn() {
    generate_monthly_invoices(ctx)
  })
}
```

### Database Schema

```sql
CREATE TABLE push_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id UUID REFERENCES subscribers(id) NOT NULL,
  token         TEXT NOT NULL,
  platform      TEXT NOT NULL,     -- fcm/apns/expo
  registered_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(subscriber_id, token)
);
```

### API Endpoints

```
GET  /v1/notifications/templates
POST /v1/notifications/send
POST /v1/notifications/bulk
GET  /v1/notifications/history
POST /v1/self/push-token        (register device token dari mobile app)
```

---

## 7. Mobile App UCP

### Stack

- **React Native + Expo** — Android + iOS dari satu codebase
- **Expo Notifications** — FCM (Android) + APNs (iOS)
- **React Query** — server state management
- **expo-camera** — QR scanner voucher
- **expo-barcode-scanner** — scan kode

### Screen Architecture

```typescript
// mobile/src/App.tsx

// Routes:
// /login          → LoginScreen (username/pass + social login)
// /dashboard      → DashboardScreen (quota gauge, expiry, status)
// /topup          → TopupScreen (pilih paket, pilih payment)
// /voucher        → VoucherScanScreen (kamera + manual input)
// /history        → SessionHistoryScreen
// /invoices       → InvoiceListScreen + PDF viewer
// /profile        → ProfileScreen (ganti password, verifikasi)
// /notifications  → NotificationCenterScreen

function DashboardScreen() {
  const { data: quota } = useQuery({
    queryKey: ['quota'],
    queryFn: () => api.getMyQuota(),
    refetchInterval: 60_000,
  });

  return (
    <View>
      <QuotaGaugeCircular
        used={quota?.used_bytes}
        limit={quota?.limit_bytes}
        isFup={quota?.is_fup_active}
      />
      <ExpiryCountdown expiresAt={quota?.expires_at} />
      <ActiveSessionBadge />
      <QuickActions>
        <TopupButton />
        <ScanVoucherButton />
        <DisconnectSessionButton />
      </QuickActions>
    </View>
  );
}
```

### Push Notification Handler

```typescript
// mobile/src/notifications/handler.ts
import * as Notifications from 'expo-notifications';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

async function registerForPushNotifications() {
  const token = await Notifications.getExpoPushTokenAsync();
  await api.registerPushToken(token.data);
}
```

### Self-Registration + Verifikasi

```gleam
pub type RegistrationRequest {
  RegistrationRequest(
    username: String,
    password: String,
    email: Option(String),
    phone: Option(String),
    verification_method: VerificationMethod,
    social_provider: Option(SocialProvider),
    social_token: Option(String),
    tenant_id: String,
    voucher_code: Option(String),
  )
}

pub type VerificationMethod {
  SMS(otp_code: String)
  Email(token: String)
  Social               // verified via OAuth
  None                 // admin-controlled tenant
}
```

### API Self-Service (UCP)

```
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
```

---

## 8. SSO / SAML / OAuth2 / ZITADEL

### Auth Middleware (Gleam)

```gleam
// apps/api_server/src/middleware/auth_middleware.gleam

// Dua mode auth:
// 1. API Key (untuk FreeRADIUS rlm_rest → Gleam internal)
// 2. JWT dari ZITADEL (untuk UI dashboard + mobile app)

pub fn authenticate(req: Request, ctx: Context)
  -> Result(AuthContext, AuthError) {
  case wisp.get_header(req, "authorization") {
    Ok("Bearer " <> token) -> verify_jwt(token, ctx.zitadel_config)
    Ok("ApiKey " <> key)   -> verify_api_key(key, ctx)
    _                      -> Error(Unauthenticated)
  }
}

pub fn verify_jwt(token: String, config: ZitadelConfig)
  -> Result(AuthContext, AuthError) {
  // Verifikasi signature via ZITADEL JWKS endpoint
  // Extract: sub, realm_access.roles, tenant_id (custom claim)
  jwks_verifier.verify(token, config.jwks_url)
  |> result.map(fn(claims) {
    AuthContext(
      user_id: claims.sub,
      tenant_id: get_claim(claims, "tenant_id"),
      roles: get_roles(claims),
      auth_method: JwtAuth,
    )
  })
}
```

### ZITADEL Tenant/Project Configuration

```
ZITADEL Project: "oxion-platform"

Clients:
  - oxion-api         (confidential, service account)
  - web-ui            (public, PKCE)
  - mobile-app        (public, PKCE)

Identity Providers:
  - Google            (OAuth2/OIDC)
  - Facebook          (OAuth2)
  - Apple             (OAuth2)
  - SAML 2.0          (enterprise SSO)

Custom Claims Mapper:
  - tenant_id         → dari user attribute
  - reseller_id       → dari user attribute
  - operator_role     → dari group membership

Session Settings:
  - Access token lifespan: 15 menit
  - Refresh token lifespan: 7 hari
  - SSO session idle: 30 menit
```

### Social Login Flow

```
1. User klik "Login dengan Google" di UI
2. UI redirect ke ZITADEL /authorize endpoint
3. ZITADEL redirect ke Google OAuth2
4. Google callback ke ZITADEL
5. ZITADEL issue JWT dengan claims (sub, tenant_id, role)
6. UI terima JWT, simpan ke localStorage/secure storage
7. Setiap request ke API: Authorization: Bearer {jwt}
8. oxRADIUS/oxCore verifikasi JWT via JWKS
```

---

## 9. Audit Log & GDPR Compliance

### Audit Engine

```gleam
// apps/audit_engine/src/audit_engine.gleam

pub type AuditEvent {
  AuditEvent(
    id: String,
    tenant_id: String,
    actor_id: String,
    actor_role: String,
    action: AuditAction,
    resource_type: String,
    resource_id: String,
    old_value: Option(Json),
    new_value: Option(Json),
    ip_address: String,
    user_agent: String,
    timestamp: DateTime,
    success: Bool,
    error: Option(String),
  )
}

pub type AuditAction {
  Create
  Update
  Delete
  Login
  Logout
  LoginFailed
  PasswordReset
  CoaTrigger
  Disconnect
  DataExport
  BulkImport
  InvoiceGenerate
  PaymentProcess
  ConsentGiven
  ConsentRevoked
  DataDeletion     // GDPR right-to-erasure
  ServiceActivate
  ServiceSuspend
  ServiceTerminate
  OtaScheduled
  OtaCompleted
}

// Setiap handler wajib emit audit event
pub fn emit(event: AuditEvent, ctx: Context) -> Result(Nil, AuditError) {
  // Insert ke audit_log table (append-only, NO UPDATE/DELETE)
  // Publish ke NATS aaa.audit.{tenant_id}
  db.insert_audit(event, ctx.db)
}
```

### GDPR Tools

```gleam
// apps/audit_engine/src/gdpr_exporter.gleam

// Right to Access: export semua data subscriber
pub fn export_subscriber_data(
  subscriber_id: String,
  ctx: Context,
) -> Result(GdprDataPackage, GdprError) {
  use profile    <- result.try(db.get_subscriber(subscriber_id, ctx.db))
  use sessions   <- result.try(db.get_all_sessions(subscriber_id, ctx.db))
  use accounting <- result.try(db.get_all_accounting(subscriber_id, ctx.db))
  use invoices   <- result.try(db.get_all_invoices(subscriber_id, ctx.db))
  use audit_log  <- result.try(db.get_audit_log(subscriber_id, ctx.db))

  let package = GdprDataPackage(
    exported_at: datetime.now(),
    subscriber: profile,
    sessions: sessions,
    accounting: accounting,
    invoices: invoices,
    audit_log: audit_log,
  )

  // Generate ZIP dengan CSV per kategori
  gdpr_zip_generator.generate(package)
}

// Right to Erasure
pub fn erase_subscriber(
  subscriber_id: String,
  ctx: Context,
) -> Result(ErasureReport, GdprError) {
  // Anonymize: ganti username/email/phone dengan SHA256 hash
  // Retain accounting records dengan anonymized ID (wajib hukum)
  // Hard delete: password_hash, personal contact info
  // Catat erasure event di audit_log
}
```

### Consent Management

```gleam
// apps/audit_engine/src/consent_manager.gleam

pub type ConsentRecord {
  ConsentRecord(
    subscriber_id: String,
    tenant_id: String,
    consent_type: ConsentType,
    given_at: DateTime,
    ip_address: String,
    version: String,
    revoked_at: Option(DateTime),
  )
}

pub type ConsentType {
  TermsOfService
  PrivacyPolicy
  MarketingEmail
  MarketingSMS
  MarketingWhatsApp
  ThirdPartyDataSharing
}
```

### Database Schema

```sql
-- AUDIT LOG (append-only, tidak boleh ada UPDATE/DELETE)
CREATE TABLE audit_log (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL,
  actor_id      UUID NOT NULL,
  actor_role    TEXT NOT NULL,
  action        TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id   TEXT,
  old_value     JSONB,
  new_value     JSONB,
  ip_address    INET,
  user_agent    TEXT,
  success       BOOLEAN NOT NULL,
  error_msg     TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON audit_log(tenant_id, created_at DESC);
CREATE INDEX ON audit_log(actor_id, created_at DESC);
CREATE INDEX ON audit_log(resource_type, resource_id);

-- CONSENT (GDPR)
CREATE TABLE consent_records (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id  UUID REFERENCES subscribers(id) NOT NULL,
  tenant_id      UUID REFERENCES tenants(id) NOT NULL,
  consent_type   TEXT NOT NULL,
  policy_version TEXT NOT NULL,
  given_at       TIMESTAMPTZ NOT NULL,
  ip_address     INET,
  revoked_at     TIMESTAMPTZ
);
```

### API Endpoints

```
GET    /v1/audit-log                          (filter: tenant, actor, resource, action, date)
GET    /v1/subscribers/:id/gdpr/export        (Right to Access)
DELETE /v1/subscribers/:id/gdpr/erase         (Right to Erasure)
GET    /v1/subscribers/:id/consent
POST   /v1/subscribers/:id/consent
DELETE /v1/subscribers/:id/consent/:type      (revoke consent)
```

---

## 10. Plugin Architecture (Enterprise Customization)

Oxion menyediakan plugin architecture agar flow bisnis dapat sangat customizable per perusahaan tanpa fork core codebase.

### Extension Surfaces

- **Flow Plugin (oxCore):** `before_step`, `after_step`, `on_error`, `on_compensate`
- **Policy Plugin (oxRADIUS):** `pre_authorize`, `post_authorize`, `accounting_transform`
- **Billing Plugin (oxBill):** `invoice_enrich`, `payment_route`, `commission_rule`
- **UI Plugin:** `menu_extend`, `dashboard_widget`, `custom_page`
- **Integration Plugin:** `outbound_event_handler`, `inbound_webhook_adapter`

### Guardrails

- Aktivasi plugin bersifat tenant-scoped.
- Plugin dijalankan melalui runner terisolasi dengan timeout dan quota.
- Runtime plugin v1 dibatasi ke TypeScript, Python, dan Elixir.
- Permission plugin berbasis allowlist.
- Semua eksekusi plugin wajib tercatat pada audit log.

### API Draft

```http
POST   /v1/plugins/upload
POST   /v1/plugins/:id/verify
POST   /v1/plugins/:id/enable?scope=tenant&tenant_id={id}
POST   /v1/plugins/:id/disable?scope=tenant&tenant_id={id}
POST   /v1/plugins/:id/rollback
GET    /v1/plugins
GET    /v1/plugins/:id/executions
```

Detail lengkap ada di `../plugins/oxion-plugin-architecture.md`.
