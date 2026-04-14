// AUTO-GENERATED FROM GLEAM PACKAGE INTERFACES.
// Source of truth: public Gleam types/functions in packages/policy + packages/interop
// Generator entrypoint: /scripts/generate-contracts.mjs

// package: oxion_policy@1.0.0
export namespace oxion_policy_evaluator {
  export type EvaluationError = { tag: "EvaluationError"; code: string; stage_id: string; path: string; reason: string };
  export type EvaluationResult = { tag: "EvaluationResult"; matches: Array<StageMatch> };
  export type StageMatch = { tag: "StageMatch"; stage_id: string; actions: Array<oxion_policy_types.Action> };
  export type Fn_evaluate = (arg0: oxion_policy_types.Policy, arg1: oxion_policy_types.Context) => { tag: "Ok"; value: EvaluationResult } | { tag: "Error"; error: EvaluationError };
}

export namespace oxion_policy_lifecycle {
  export type ActivationError = { tag: "PolicyNotPublished"; status: LifecycleStatus } | { tag: "ActivePolicyConflict" } | { tag: "PolicyImmutableArchived" };
  export type ActivationState = { tag: "ActivationState"; status: LifecycleStatus; is_active: boolean };
  export type LifecycleStatus = { tag: "Draft" } | { tag: "Simulated" } | { tag: "Published" } | { tag: "Archived" };
  export type TransitionError = { tag: "InvalidTransition"; from: LifecycleStatus; to: LifecycleStatus };
  export type Fn_activate = (arg0: ActivationState, arg1: boolean) => { tag: "Ok"; value: ActivationState } | { tag: "Error"; error: ActivationError };
  export type Fn_can_activate = (arg0: LifecycleStatus) => boolean;
  export type Fn_can_transition = (arg0: LifecycleStatus, arg1: LifecycleStatus) => boolean;
  export type Fn_deactivate = (arg0: ActivationState) => ActivationState;
  export type Fn_is_mutable = (arg0: LifecycleStatus) => boolean;
  export type Fn_transition = (arg0: LifecycleStatus, arg1: LifecycleStatus) => { tag: "Ok"; value: LifecycleStatus } | { tag: "Error"; error: TransitionError };
}

export namespace oxion_policy_simulator {
  export type SimulationError = { tag: "InvalidRange" } | { tag: "EvaluationFailed"; _0: oxion_policy_evaluator.EvaluationError };
  export type SimulationMatch = { tag: "SimulationMatch"; stage_id: string; actions: Array<oxion_policy_types.Action>; reason: string };
  export type SimulationRow = { tag: "SimulationRow"; day: number; matches: Array<SimulationMatch> };
  export type Fn_simulate_days = (arg0: oxion_policy_types.Policy, arg1: oxion_policy_types.Context, arg2: number, arg3: number) => { tag: "Ok"; value: Array<SimulationRow> } | { tag: "Error"; error: SimulationError };
}

export namespace oxion_policy_types {
  export type Action = { tag: "ApplyBandwidthProfile"; profile_id: string } | { tag: "SuspendService"; reason: string } | { tag: "RestoreService" } | { tag: "SendNotification"; template_id: string; include_payment_link: boolean; channels: Array<NotificationChannel> } | { tag: "EmitEvent"; topic: string; payload: JsonValue | null } | { tag: "SetOperationalState"; state: string } | { tag: "RunPluginHook"; plugin_id: string; hook: string; payload: JsonValue | null };
  export type Condition = { tag: "All"; _0: Array<Condition> } | { tag: "Any"; _0: Array<Condition> } | { tag: "Rule"; field: Field; op: Operator; value: Value; enabled: boolean };
  export type Context = { tag: "Context"; days_past_due: number; invoice_status: string; operational_state: string; billing_plan: string; total_due_amount: number; is_paid: boolean };
  export type Field = { tag: "DaysPastDue" } | { tag: "InvoiceStatus" } | { tag: "OperationalState" } | { tag: "BillingPlan" } | { tag: "TotalDueAmount" } | { tag: "IsPaid" };
  export type JsonValue = { tag: "JsonNull" } | { tag: "JsonBool"; _0: boolean } | { tag: "JsonInt"; _0: number } | { tag: "JsonFloat"; _0: number } | { tag: "JsonString"; _0: string } | { tag: "JsonArray"; _0: Array<JsonValue> } | { tag: "JsonObject"; _0: Array<[string, JsonValue]> };
  export type NotificationChannel = { tag: "Whatsapp" } | { tag: "Telegram" } | { tag: "Sms" } | { tag: "Email" } | { tag: "Push" };
  export type Operator = { tag: "Eq" } | { tag: "Ne" } | { tag: "Gt" } | { tag: "Gte" } | { tag: "Lt" } | { tag: "Lte" } | { tag: "In" } | { tag: "NotIn" } | { tag: "Between" } | { tag: "IsTrue" } | { tag: "IsFalse" };
  export type PaymentLinkMode = { tag: "StaticPaymentLink" } | { tag: "SignedPaymentLink" };
  export type Policy = { tag: "Policy"; name: string; description: string | null; grace_days: number; timezone: string; context: PolicyContextConfig | null; stages: Array<Stage> };
  export type PolicyContextConfig = { tag: "PolicyContextConfig"; evaluation_time: string | null; payment_link_mode: PaymentLinkMode | null; payment_link_base_url: string | null; payment_link_ttl_minutes: number | null };
  export type Scalar = { tag: "IntValue"; _0: number } | { tag: "StringValue"; _0: string } | { tag: "BoolValue"; _0: boolean };
  export type Stage = { tag: "Stage"; id: string; priority: number; condition: Condition; actions: Array<Action>; stop_on_match: boolean; notification_template: string | null; enabled: boolean };
  export type Value = { tag: "ScalarValue"; _0: Scalar } | { tag: "ListValue"; _0: Array<Scalar> } | { tag: "BetweenValue"; min: number; max: number } | { tag: "NoValue" };
}

export namespace oxion_policy_validator {
  export type ValidationCode = { tag: "EmptyConditionGroupCode" } | { tag: "InvalidOperatorForFieldCode" } | { tag: "MissingRequiredValueCode" } | { tag: "UnexpectedValueCode" } | { tag: "InvalidValueTypeCode" } | { tag: "InvalidBetweenRangeCode" } | { tag: "InvalidStagePriorityCode" } | { tag: "DuplicateStageIdCode" } | { tag: "MissingStagesCode" } | { tag: "MissingActionsCode" } | { tag: "InvalidPolicyNameCode" } | { tag: "InvalidPolicyDescriptionCode" } | { tag: "InvalidTimezoneCode" } | { tag: "InvalidGraceDaysCode" } | { tag: "InvalidStageIdCode" } | { tag: "InvalidNotificationTemplateCode" } | { tag: "InvalidActionConfigCode" } | { tag: "InvalidContextConfigCode" };
  export type ValidationError = { tag: "ValidationError"; code: ValidationCode; path: string; reason: string };
  export type Fn_validate_policy = (arg0: oxion_policy_types.Policy) => { tag: "Ok"; value: null } | { tag: "Error"; error: Array<ValidationError> };
}

// package: oxion_interop@1.0.0
export namespace oxion_radius_coa_result {
  export type CoaExecutionResult = { tag: "IdempotentSkip"; reason: string } | { tag: "ReplayRejected"; reason: string } | { tag: "Ack"; applied_target: string; retries: number } | { tag: "Nak"; code: string; message: string; retries: number } | { tag: "Timeout"; retries: number } | { tag: "SnapshotUnavailable"; reason: string } | { tag: "ProfileResolutionFailed"; reason: string } | { tag: "BuildRejected"; reason: string } | { tag: "InvalidRetryPolicy"; reason: string } | { tag: "TransportFailed"; reason: string; retries: number };
  export type Fn_reason = (arg0: CoaExecutionResult) => string | null;
  export type Fn_retry_count = (arg0: CoaExecutionResult) => number;
}

export type GeneratedContractStatus = "gleam_source_of_truth";
