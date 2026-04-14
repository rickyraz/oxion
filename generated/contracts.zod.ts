// AUTO-GENERATED ZOD SCHEMAS FROM GLEAM PACKAGE INTERFACES.
// Source interfaces: generated/interfaces/*.interface.json
// Mapping layer: interface.json -> Zod model -> TypeScript renderer
// Generator entrypoint: /scripts/generate-zod.ts
import { z } from "zod";

// package: oxion_interop@1.0.0
export namespace oxion_radius_coa_result {
  export const CoaExecutionResult: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("IdempotentSkip"), reason: z.string() }), z.object({ tag: z.literal("ReplayRejected"), reason: z.string() }), z.object({ tag: z.literal("Ack"), applied_target: z.string(), retries: z.number().int() }), z.object({ tag: z.literal("Nak"), code: z.string(), message: z.string(), retries: z.number().int() }), z.object({ tag: z.literal("Timeout"), retries: z.number().int() }), z.object({ tag: z.literal("SnapshotUnavailable"), reason: z.string() }), z.object({ tag: z.literal("ProfileResolutionFailed"), reason: z.string() }), z.object({ tag: z.literal("BuildRejected"), reason: z.string() }), z.object({ tag: z.literal("InvalidRetryPolicy"), reason: z.string() }), z.object({ tag: z.literal("TransportFailed"), reason: z.string(), retries: z.number().int() })]));
  export type CoaExecutionResult = z.infer<typeof CoaExecutionResult>;
  export const Fn_reason_params = z.tuple([CoaExecutionResult]);
  export const Fn_reason_return = z.string().nullable();
  export const Fn_retry_count_params = z.tuple([CoaExecutionResult]);
  export const Fn_retry_count_return = z.number().int();
}

// package: oxion_policy@1.0.0
export namespace oxion_policy_evaluator {
  export const EvaluationError: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("EvaluationError"), code: z.string(), stage_id: z.string(), path: z.string(), reason: z.string() }));
  export type EvaluationError = z.infer<typeof EvaluationError>;
  export const EvaluationResult: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("EvaluationResult"), matches: z.array(StageMatch) }));
  export type EvaluationResult = z.infer<typeof EvaluationResult>;
  export const StageMatch: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("StageMatch"), stage_id: z.string(), actions: z.array(oxion_policy_types.Action) }));
  export type StageMatch = z.infer<typeof StageMatch>;
  export const Fn_evaluate_params = z.tuple([oxion_policy_types.Policy, oxion_policy_types.Context]);
  export const Fn_evaluate_return = z.union([z.object({ tag: z.literal("Ok"), value: EvaluationResult }), z.object({ tag: z.literal("Error"), error: EvaluationError })]);
}

export namespace oxion_policy_lifecycle {
  export const ActivationError: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("PolicyNotPublished"), status: LifecycleStatus }), z.object({ tag: z.literal("ActivePolicyConflict") }), z.object({ tag: z.literal("PolicyImmutableArchived") })]));
  export type ActivationError = z.infer<typeof ActivationError>;
  export const ActivationState: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("ActivationState"), status: LifecycleStatus, is_active: z.boolean() }));
  export type ActivationState = z.infer<typeof ActivationState>;
  export const LifecycleStatus: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("Draft") }), z.object({ tag: z.literal("Simulated") }), z.object({ tag: z.literal("Published") }), z.object({ tag: z.literal("Archived") })]));
  export type LifecycleStatus = z.infer<typeof LifecycleStatus>;
  export const TransitionError: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("InvalidTransition"), from: LifecycleStatus, to: LifecycleStatus }));
  export type TransitionError = z.infer<typeof TransitionError>;
  export const Fn_activate_params = z.tuple([ActivationState, z.boolean()]);
  export const Fn_activate_return = z.union([z.object({ tag: z.literal("Ok"), value: ActivationState }), z.object({ tag: z.literal("Error"), error: ActivationError })]);
  export const Fn_can_activate_params = z.tuple([LifecycleStatus]);
  export const Fn_can_activate_return = z.boolean();
  export const Fn_can_transition_params = z.tuple([LifecycleStatus, LifecycleStatus]);
  export const Fn_can_transition_return = z.boolean();
  export const Fn_deactivate_params = z.tuple([ActivationState]);
  export const Fn_deactivate_return = ActivationState;
  export const Fn_is_mutable_params = z.tuple([LifecycleStatus]);
  export const Fn_is_mutable_return = z.boolean();
  export const Fn_transition_params = z.tuple([LifecycleStatus, LifecycleStatus]);
  export const Fn_transition_return = z.union([z.object({ tag: z.literal("Ok"), value: LifecycleStatus }), z.object({ tag: z.literal("Error"), error: TransitionError })]);
}

export namespace oxion_policy_simulator {
  export const SimulationError: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("InvalidRange") }), z.object({ tag: z.literal("EvaluationFailed"), _0: oxion_policy_evaluator.EvaluationError })]));
  export type SimulationError = z.infer<typeof SimulationError>;
  export const SimulationMatch: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("SimulationMatch"), stage_id: z.string(), actions: z.array(oxion_policy_types.Action), reason: z.string() }));
  export type SimulationMatch = z.infer<typeof SimulationMatch>;
  export const SimulationRow: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("SimulationRow"), day: z.number().int(), matches: z.array(SimulationMatch) }));
  export type SimulationRow = z.infer<typeof SimulationRow>;
  export const Fn_simulate_days_params = z.tuple([oxion_policy_types.Policy, oxion_policy_types.Context, z.number().int(), z.number().int()]);
  export const Fn_simulate_days_return = z.union([z.object({ tag: z.literal("Ok"), value: z.array(SimulationRow) }), z.object({ tag: z.literal("Error"), error: SimulationError })]);
}

export namespace oxion_policy_types {
  export const Action: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("ApplyBandwidthProfile"), profile_id: z.string() }), z.object({ tag: z.literal("SuspendService"), reason: z.string() }), z.object({ tag: z.literal("RestoreService") }), z.object({ tag: z.literal("SendNotification"), template_id: z.string(), include_payment_link: z.boolean(), channels: z.array(NotificationChannel) }), z.object({ tag: z.literal("EmitEvent"), topic: z.string(), payload: JsonValue.nullable() }), z.object({ tag: z.literal("SetOperationalState"), state: z.string() }), z.object({ tag: z.literal("RunPluginHook"), plugin_id: z.string(), hook: z.string(), payload: JsonValue.nullable() })]));
  export type Action = z.infer<typeof Action>;
  export const Condition: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("All"), _0: z.array(Condition) }), z.object({ tag: z.literal("Any"), _0: z.array(Condition) }), z.object({ tag: z.literal("Rule"), field: Field, op: Operator, value: Value, enabled: z.boolean() })]));
  export type Condition = z.infer<typeof Condition>;
  export const Context: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("Context"), days_past_due: z.number().int(), invoice_status: z.string(), operational_state: z.string(), billing_plan: z.string(), total_due_amount: z.number().int(), is_paid: z.boolean() }));
  export type Context = z.infer<typeof Context>;
  export const Field: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("DaysPastDue") }), z.object({ tag: z.literal("InvoiceStatus") }), z.object({ tag: z.literal("OperationalState") }), z.object({ tag: z.literal("BillingPlan") }), z.object({ tag: z.literal("TotalDueAmount") }), z.object({ tag: z.literal("IsPaid") })]));
  export type Field = z.infer<typeof Field>;
  export const JsonValue: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("JsonNull") }), z.object({ tag: z.literal("JsonBool"), _0: z.boolean() }), z.object({ tag: z.literal("JsonInt"), _0: z.number().int() }), z.object({ tag: z.literal("JsonFloat"), _0: z.number() }), z.object({ tag: z.literal("JsonString"), _0: z.string() }), z.object({ tag: z.literal("JsonArray"), _0: z.array(JsonValue) }), z.object({ tag: z.literal("JsonObject"), _0: z.array(z.tuple([z.string(), JsonValue])) })]));
  export type JsonValue = z.infer<typeof JsonValue>;
  export const NotificationChannel: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("Whatsapp") }), z.object({ tag: z.literal("Telegram") }), z.object({ tag: z.literal("Sms") }), z.object({ tag: z.literal("Email") }), z.object({ tag: z.literal("Push") })]));
  export type NotificationChannel = z.infer<typeof NotificationChannel>;
  export const Operator: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("Eq") }), z.object({ tag: z.literal("Ne") }), z.object({ tag: z.literal("Gt") }), z.object({ tag: z.literal("Gte") }), z.object({ tag: z.literal("Lt") }), z.object({ tag: z.literal("Lte") }), z.object({ tag: z.literal("In") }), z.object({ tag: z.literal("NotIn") }), z.object({ tag: z.literal("Between") }), z.object({ tag: z.literal("IsTrue") }), z.object({ tag: z.literal("IsFalse") })]));
  export type Operator = z.infer<typeof Operator>;
  export const PaymentLinkMode: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("StaticPaymentLink") }), z.object({ tag: z.literal("SignedPaymentLink") })]));
  export type PaymentLinkMode = z.infer<typeof PaymentLinkMode>;
  export const Policy: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("Policy"), name: z.string(), description: z.string().nullable(), grace_days: z.number().int(), timezone: z.string(), context: PolicyContextConfig.nullable(), stages: z.array(Stage) }));
  export type Policy = z.infer<typeof Policy>;
  export const PolicyContextConfig: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("PolicyContextConfig"), evaluation_time: z.string().nullable(), payment_link_mode: PaymentLinkMode.nullable(), payment_link_base_url: z.string().nullable(), payment_link_ttl_minutes: z.number().int().nullable() }));
  export type PolicyContextConfig = z.infer<typeof PolicyContextConfig>;
  export const Scalar: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("IntValue"), _0: z.number().int() }), z.object({ tag: z.literal("StringValue"), _0: z.string() }), z.object({ tag: z.literal("BoolValue"), _0: z.boolean() })]));
  export type Scalar = z.infer<typeof Scalar>;
  export const Stage: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("Stage"), id: z.string(), priority: z.number().int(), condition: Condition, actions: z.array(Action), stop_on_match: z.boolean(), notification_template: z.string().nullable(), enabled: z.boolean() }));
  export type Stage = z.infer<typeof Stage>;
  export const Value: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("ScalarValue"), _0: Scalar }), z.object({ tag: z.literal("ListValue"), _0: z.array(Scalar) }), z.object({ tag: z.literal("BetweenValue"), min: z.number().int(), max: z.number().int() }), z.object({ tag: z.literal("NoValue") })]));
  export type Value = z.infer<typeof Value>;
}

export namespace oxion_policy_validator {
  export const ValidationCode: z.ZodTypeAny = z.lazy(() => z.union([z.object({ tag: z.literal("EmptyConditionGroupCode") }), z.object({ tag: z.literal("InvalidOperatorForFieldCode") }), z.object({ tag: z.literal("MissingRequiredValueCode") }), z.object({ tag: z.literal("UnexpectedValueCode") }), z.object({ tag: z.literal("InvalidValueTypeCode") }), z.object({ tag: z.literal("InvalidBetweenRangeCode") }), z.object({ tag: z.literal("InvalidStagePriorityCode") }), z.object({ tag: z.literal("DuplicateStageIdCode") }), z.object({ tag: z.literal("MissingStagesCode") }), z.object({ tag: z.literal("MissingActionsCode") }), z.object({ tag: z.literal("InvalidPolicyNameCode") }), z.object({ tag: z.literal("InvalidPolicyDescriptionCode") }), z.object({ tag: z.literal("InvalidTimezoneCode") }), z.object({ tag: z.literal("InvalidGraceDaysCode") }), z.object({ tag: z.literal("InvalidStageIdCode") }), z.object({ tag: z.literal("InvalidNotificationTemplateCode") }), z.object({ tag: z.literal("InvalidActionConfigCode") }), z.object({ tag: z.literal("InvalidContextConfigCode") })]));
  export type ValidationCode = z.infer<typeof ValidationCode>;
  export const ValidationError: z.ZodTypeAny = z.lazy(() => z.object({ tag: z.literal("ValidationError"), code: ValidationCode, path: z.string(), reason: z.string() }));
  export type ValidationError = z.infer<typeof ValidationError>;
  export const Fn_validate_policy_params = z.tuple([oxion_policy_types.Policy]);
  export const Fn_validate_policy_return = z.union([z.object({ tag: z.literal("Ok"), value: z.null() }), z.object({ tag: z.literal("Error"), error: z.array(ValidationError) })]);
}

export const GeneratedZodStatus = z.literal("gleam_source_of_truth");
