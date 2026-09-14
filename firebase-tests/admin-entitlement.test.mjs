import { promisify } from "node:util";
import { execFile } from "node:child_process";
import { test } from "node:test";
import assert from "node:assert/strict";

const run = promisify(execFile);
const projectId = "macgit-admin-script-test";

async function runEntitlementScript(mode) {
  await run(
    process.execPath,
    [new URL("../scripts/firebase/set-entitlement.mjs", import.meta.url).pathname, "user-a", mode],
    {
      env: {
        ...process.env,
        FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
        GCLOUD_PROJECT: projectId,
      },
    },
  );
}

async function entitlementData() {
  const response = await fetch(
    `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents/entitlements/user-a`,
    { headers: { Authorization: "Bearer owner" } },
  );
  assert.equal(response.ok, true);
  const document = await response.json();
  return Object.fromEntries(
    Object.entries(document.fields).map(([key, value]) => [
      key,
      value.stringValue ?? value.booleanValue ?? value.timestampValue,
    ]),
  );
}

test("admin script grants and revokes test Pro access", async () => {
  await runEntitlementScript("grant");
  const granted = await entitlementData();
  assert.equal(granted.plan, "pro");
  assert.equal(granted.access, "active");
  assert.equal(granted.billingStatus, "active");
  assert.equal(granted.source, "admin_test");

  await runEntitlementScript("revoke");
  const revoked = await entitlementData();
  assert.equal(revoked.plan, "free");
  assert.equal(revoked.access, "inactive");
  assert.equal(revoked.billingStatus, "none");
});

test("admin script publishes the release feature policy", async () => {
  const featurePolicyProjectId = "macgit-feature-policy-script-test";
  await run(
    process.execPath,
    [new URL("../scripts/firebase/set-feature-policy.mjs", import.meta.url).pathname, "release"],
    {
      env: {
        ...process.env,
        FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
        GCLOUD_PROJECT: featurePolicyProjectId,
      },
    },
  );

  const response = await fetch(
    `http://127.0.0.1:8080/v1/projects/${featurePolicyProjectId}/databases/(default)/documents/featurePolicies/release`,
    { headers: { Authorization: "Bearer owner" } },
  );
  assert.equal(response.ok, true);
  const document = await response.json();
  const fields = document.fields;

  assert.equal(fields.schemaVersion.integerValue, "1");
  assert.equal(fields.revision.integerValue, "5");
  assert.equal(
    fields.features.mapValue.fields.privateRepositories
      .mapValue.fields.plans.mapValue.fields.free
      .mapValue.fields.enabled.booleanValue,
    false,
  );
  assert.equal(
    fields.features.mapValue.fields.pullRequests
      .mapValue.fields.plans.mapValue.fields.free
      .mapValue.fields.repositoryScope.stringValue,
    "public",
  );
  assert.equal(
    fields.features.mapValue.fields.gitFlow
      .mapValue.fields.plans.mapValue.fields.free
      .mapValue.fields.repositoryScope.stringValue,
    "publicOrLocal",
  );
  assert.equal(
    fields.features.mapValue.fields.aiCommitMessage
      .mapValue.fields.plans.mapValue.fields.free
      .mapValue.fields.enabled.booleanValue,
    true,
  );
});
