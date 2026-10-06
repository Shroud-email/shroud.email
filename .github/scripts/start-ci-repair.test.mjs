import assert from "node:assert/strict";
import { test } from "node:test";
import { repairPrompt } from "./start-ci-repair.mjs";

const event = {
  action: "completed",
  repository: { id: 505987755, full_name: "Shroud-email/shroud.email" },
  workflow_run: {
    id: 37501356493,
    run_attempt: 1,
    workflow_id: 265778583,
    head_repository: { id: 505987755 },
    name: "npm_and_yarn in /website for postcss-selector-parser - Update #1613478537",
    path: "dynamic/dependabot/dependabot-updates",
    event: "dynamic",
    head_branch: "main",
    conclusion: "failure",
    head_sha: "967b55e7da44450c301173bb7ae0ab1a42c64d61",
  },
};

test("does not launch repairs for dependency-specific Dependabot run names", () => {
  assert.equal(repairPrompt(event), null);
});

test("still launches repairs for ordinary failed main workflows", () => {
  const prompt = repairPrompt({
    ...event,
    workflow_run: {
      ...event.workflow_run,
      name: "CI",
      path: ".github/workflows/ci.yml",
      event: "push",
    },
  });
  assert.ok(prompt?.startsWith("CI repair: 37501356493/1\n"));
});
