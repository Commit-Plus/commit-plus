import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AccountDeletionDependencies,
  createWebSignInTokenForUser,
  deleteAccountData,
  WebSignInTokenDependencies,
} from "./index.js";

test("web sign-in token is created for the authenticated Firebase user", async () => {
  const requestedUIDs: string[] = [];
  const dependencies: WebSignInTokenDependencies = {
    async createCustomToken(uid) {
      requestedUIDs.push(uid);
      return "custom-token";
    },
  };

  const token = await createWebSignInTokenForUser("user-a", dependencies);

  assert.equal(token, "custom-token");
  assert.deepEqual(requestedUIDs, ["user-a"]);
});

test("account deletion removes owned documents and auth user", async () => {
  const deletedPolarCustomers: Array<{ uid: string; email?: string }> = [];
  const deletedDocuments: string[] = [];
  const deletedUsers: string[] = [];
  const dependencies: AccountDeletionDependencies = {
    async beginDeletion() {},
    async deletePolarCustomer(uid, email) {
      deletedPolarCustomers.push({ uid, email });
    },
    async deleteDocument(path) { deletedDocuments.push(path); },
    async deleteCollection(path) { deletedCollections.push(path); },
    async deleteUser(uid) { deletedUsers.push(uid); },
  };
  const deletedCollections: string[] = [];

  await deleteAccountData("user-a", dependencies, "user@example.com");

  assert.deepEqual(deletedPolarCustomers, [
    { uid: "user-a", email: "user@example.com" },
  ]);
  assert.deepEqual(deletedDocuments.sort(), [
    "entitlements/user-a",
    "users/user-a/deviceAccess/summary",
    "users/user-a/settings/app",
  ]);
  assert.deepEqual(deletedCollections.sort(), [
    "users/user-a/aiOutbox",
    "users/user-a/aiPeriods",
    "users/user-a/aiRequestIDs",
    "users/user-a/aiRequests",
    "users/user-a/aiState",
    "users/user-a/devices",
    "users/user-a/gitFlowConfigurations",
    "users/user-a/gitProviderAccounts",
    "users/user-a/repositoryBookmarks",
  ]);
  assert.deepEqual(deletedUsers, ["user-a"]);
});

test("account deletion is idempotent when the auth user is already absent", async () => {
  const dependencies: AccountDeletionDependencies = {
    async beginDeletion() {},
    async deletePolarCustomer() {},
    async deleteDocument() {},
    async deleteCollection() {},
    async deleteUser() {
      throw { code: "auth/user-not-found" };
    },
  };

  await assert.doesNotReject(deleteAccountData("user-a", dependencies));
});

test("unexpected auth deletion failures propagate", async () => {
  const dependencies: AccountDeletionDependencies = {
    async beginDeletion() {},
    async deletePolarCustomer() {},
    async deleteDocument() {},
    async deleteCollection() {},
    async deleteUser() {
      throw new Error("auth unavailable");
    },
  };

  await assert.rejects(deleteAccountData("user-a", dependencies), /auth unavailable/);
});

test("Polar deletion failure preserves Firebase account data for retry", async () => {
  let firebaseDeletionAttempted = false;
  const dependencies: AccountDeletionDependencies = {
    async beginDeletion() {},
    async deletePolarCustomer() {
      throw new Error("polar unavailable");
    },
    async deleteDocument() { firebaseDeletionAttempted = true; },
    async deleteCollection() { firebaseDeletionAttempted = true; },
    async deleteUser() { firebaseDeletionAttempted = true; },
  };

  await assert.rejects(deleteAccountData("user-a", dependencies), /polar unavailable/);
  assert.equal(firebaseDeletionAttempted, false);
});


test("deletion fence precedes every external or local deletion and remains after completion", async () => {
  const calls: string[] = [];
  const dependencies: AccountDeletionDependencies = {
    async beginDeletion() { calls.push("fence"); },
    async deletePolarCustomer() { calls.push("polar"); },
    async deleteDocument(path) { assert.ok(!path.startsWith("accountDeletionFences/")); calls.push("document"); },
    async deleteCollection() { calls.push("collection"); },
    async deleteUser() { calls.push("auth"); },
  };
  await deleteAccountData("user-a", dependencies);
  assert.deepEqual(calls.slice(0, 2), ["fence", "polar"]);
  assert.equal(calls.at(-1), "auth");
});
