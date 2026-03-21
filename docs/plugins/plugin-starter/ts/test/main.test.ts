import test from "node:test";
import assert from "node:assert/strict";

import { before_step } from "../src/main";

test("returns allow for non-targeted step", async () => {
  const result = await before_step({
    tenant_id: "tnt_001",
    workflow: { job_id: "job_1", step: "suspend_service" },
    config: { target_step: "activate_service", auto_allow: true }
  });

  assert.equal(result.decision, "allow");
  assert.equal(result.reason, "step_not_targeted");
});

test("requires manual approval when auto_allow disabled", async () => {
  const result = await before_step({
    tenant_id: "tnt_001",
    workflow: { job_id: "job_2", step: "activate_service" },
    config: { target_step: "activate_service", auto_allow: false }
  });

  assert.equal(result.decision, "require_manual_approval");
  assert.equal(result.reason, "manual_review_required");
});
