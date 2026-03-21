// TypeScript starter plugin untuk Oxion Plugin Runner.

export type Decision = "allow" | "deny" | "require_manual_approval";

export type HookPayload = {
  tenant_id: string;
  workflow: {
    job_id: string;
    step: string;
    payload?: Record<string, unknown>;
  };
  config: {
    target_step: string;
    auto_allow: boolean;
  };
};

export type HookResult = {
  decision: Decision;
  reason: string;
  patch?: Record<string, unknown>;
};

export async function before_step(input: HookPayload): Promise<HookResult> {
  if (input.workflow.step !== input.config.target_step) {
    return { decision: "allow", reason: "step_not_targeted" };
  }

  if (input.config.auto_allow) {
    return {
      decision: "allow",
      reason: "auto_allow_enabled",
      patch: {
        plugin_id: "com.oxion.plugin.starter-ts",
        plugin_note: "Allowed by TS starter plugin"
      }
    };
  }

  return {
    decision: "require_manual_approval",
    reason: "manual_review_required"
  };
}
