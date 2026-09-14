import { readFileSync } from "node:fs";
import { after, afterEach, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";

const projectId = "demo-commit-plus-ai";
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

afterEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

const deviceIDs = {
  "user-a": "00000000-0000-4000-8000-000000000001",
  "user-b": "00000000-0000-4000-8000-000000000002",
};

function deviceContext(uid) {
  return environment.authenticatedContext(uid);
}

function settings(uid, context) {
  return doc(context.firestore(), `users/${uid}/settings/app`);
}

function entitlement(uid, context) {
  return doc(context.firestore(), `entitlements/${uid}`);
}

function releaseFeaturePolicy(context) {
  return doc(context.firestore(), "featurePolicies/release");
}

function gitProviderAccount(uid, connectionID, context) {
  return doc(context.firestore(), `users/${uid}/gitProviderAccounts/${connectionID}`);
}

function repositoryBookmark(uid, bookmarkID, context) {
  return doc(context.firestore(), `users/${uid}/repositoryBookmarks/${bookmarkID}`);
}

function gitFlowConfiguration(uid, repositoryID, context) {
  return doc(context.firestore(), `users/${uid}/gitFlowConfigurations/${repositoryID}`);
}

function device(uid, deviceID, context) {
  return doc(context.firestore(), `users/${uid}/devices/${deviceID}`);
}

function deviceSummary(uid, context) {
  return doc(context.firestore(), `users/${uid}/deviceAccess/summary`);
}

function validDeviceRecord(overrides = {}) {
  return {
    schemaVersion: 1,
    deviceID: deviceIDs["user-a"],
    status: "active",
    platform: "macOS",
    modelFamily: "MacBook Pro",
    osVersion: "26.2",
    appVersion: "1.0.4",
    createdAt: serverTimestamp(),
    lastSeenAt: serverTimestamp(),
    ...overrides,
  };
}

function validSettings() {
  return {
    schemaVersion: 1,
    appearance: "dark",
    showToolbarButtonText: true,
    showSubmodules: false,
    showSubtrees: true,
    showHeaderBranchButton: true,
    showHeaderMergeButton: false,
    showHeaderStashButton: true,
    showHeaderUndoButton: true,
    showHeaderRemoteButton: false,
    showHeaderFinderButton: true,
    showHeaderEditorButton: true,
    showHeaderTerminalButton: false,
    showHeaderSettingsButton: false,
    historyBranchFilter: "branch:origin/feature/login",
    historyIncludeRemotes: true,
    autoFetchEnabled: true,
    refreshOnAppActive: false,
    updatedAt: serverTimestamp(),
  };
}

function validGitProviderAccount() {
  return {
    schemaVersion: 1,
    provider: "github",
    hostURL: "https://github.com",
    providerUserID: "583231",
    username: "octocat",
    displayName: "The Octocat",
    avatarURL: "https://avatars.githubusercontent.com/u/583231",
    scopes: ["repo", "read:user"],
    permissions: {},
    tokenStatus: "valid",
    transportProtocol: "https",
    connectedAt: serverTimestamp(),
    lastValidatedAt: serverTimestamp(),
  };
}

function validRepositoryBookmark() {
  return {
    schemaVersion: 1,
    canonicalKey: "github.com/openai/codex",
    name: "codex",
    provider: "github",
    host: "github.com",
    ownerPath: "openai",
    remoteURL: "https://github.com/openai/codex.git",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function validGitFlowConfiguration() {
  return {
    schemaVersion: 1,
    canonicalKey: "github.com/openai/codex",
    isEnabled: true,
    mainBranch: "main",
    developBranch: "develop",
    featurePrefix: "feature/",
    bugfixPrefix: "bugfix/",
    releasePrefix: "release/",
    hotfixPrefix: "hotfix/",
    topicFinishStrategy: "mergeNoFastForward",
    createReleaseTagOnFinish: true,
    createHotfixTagOnFinish: true,
    updatedAt: serverTimestamp(),
  };
}

describe("Firestore ownership rules", () => {
  test("a user can read and write only their own settings", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");

    await assertSucceeds(setDoc(settings("user-a", userA), validSettings()));
    await assertSucceeds(getDoc(settings("user-a", userA)));
    await assertFails(getDoc(settings("user-a", userB)));
    await assertFails(setDoc(settings("user-a", userB), validSettings()));
  });

  test("settings reject missing and unknown fields", async () => {
    const userA = deviceContext("user-a");
    const optionalFields = new Set([
      "appearance",
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderUndoButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderEditorButton",
      "showHeaderTerminalButton",
      "showHeaderSettingsButton",
      "historyBranchFilter",
      "historyIncludeRemotes",
      "autoFetchEnabled",
      "refreshOnAppActive",
    ]);

    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      unexpected: true,
    }));

    for (const key of Object.keys(validSettings())) {
      if (optionalFields.has(key)) continue;
      const missingField = validSettings();
      delete missingField[key];
      await assertFails(setDoc(settings("user-a", userA), missingField));
    }
  });

  test("settings reject unsupported schema versions and every wrong field type", async () => {
    const userA = deviceContext("user-a");
    const invalidValues = {
      schemaVersion: 2,
      appearance: true,
      showToolbarButtonText: "true",
      showSubmodules: "false",
      showSubtrees: 1,
      historyBranchFilter: 123,
      historyIncludeRemotes: "true",
      updatedAt: "now",
    };

    for (const [key, value] of Object.entries(invalidValues)) {
      await assertFails(setDoc(settings("user-a", userA), {
        ...validSettings(),
        [key]: value,
      }));
    }
  });

  test("settings accept optional settings fields", async () => {
    const userA = deviceContext("user-a");

    await assertSucceeds(setDoc(settings("user-a", userA), validSettings()));
  });

  test("settings reject wrong type for optional settings fields", async () => {
    const userA = deviceContext("user-a");

    for (const key of [
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderUndoButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderEditorButton",
      "showHeaderTerminalButton",
      "showHeaderSettingsButton",
      "historyIncludeRemotes",
      "autoFetchEnabled",
      "refreshOnAppActive",
    ]) {
      await assertFails(setDoc(settings("user-a", userA), {
        ...validSettings(),
        [key]: "true",
      }));
    }

    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      historyBranchFilter: 123,
    }));
    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      historyBranchFilter: "branch:",
    }));
    await assertFails(setDoc(settings("user-a", userA), {
      ...validSettings(),
      appearance: "sepia",
    }));
  });

  test("settings accept legacy documents without header button fields", async () => {
    const userA = deviceContext("user-a");
    const legacy = validSettings();
    for (const key of [
      "appearance",
      "showHeaderBranchButton",
      "showHeaderMergeButton",
      "showHeaderStashButton",
      "showHeaderUndoButton",
      "showHeaderRemoteButton",
      "showHeaderFinderButton",
      "showHeaderEditorButton",
      "showHeaderTerminalButton",
      "showHeaderSettingsButton",
      "historyBranchFilter",
      "historyIncludeRemotes",
      "autoFetchEnabled",
      "refreshOnAppActive",
    ]) {
      delete legacy[key];
    }

    await assertSucceeds(setDoc(settings("user-a", userA), legacy));
  });

  test("a user can read only their own entitlement", async () => {
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), {
        plan: "pro",
        access: "active",
        billingStatus: "active",
      });
    });
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");

    await assertSucceeds(getDoc(entitlement("user-a", userA)));
    await assertFails(getDoc(entitlement("user-a", userB)));
  });

  test("a user can read and write only their own Git provider metadata", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
    const ownAccount = gitProviderAccount("user-a", "connection-1", userA);

    await assertSucceeds(setDoc(ownAccount, validGitProviderAccount()));
    await assertSucceeds(getDoc(ownAccount));
    await assertFails(getDoc(gitProviderAccount("user-a", "connection-1", userB)));
    await assertFails(setDoc(
      gitProviderAccount("user-a", "connection-1", userB),
      validGitProviderAccount(),
    ));
  });

  test("Git provider metadata rejects secrets and unsupported providers", async () => {
    const userA = deviceContext("user-a");
    const account = gitProviderAccount("user-a", "connection-1", userA);

    await assertFails(setDoc(account, {
      ...validGitProviderAccount(),
      accessToken: "must-not-be-stored",
    }));
    await assertFails(setDoc(account, {
      ...validGitProviderAccount(),
      provider: "unsupported",
    }));
  });

  test("Git provider metadata accepts Bitbucket without storing its API token", async () => {
    const userA = deviceContext("user-a");

    await assertSucceeds(setDoc(
      gitProviderAccount("user-a", "bitbucket-connection", userA),
      {
        ...validGitProviderAccount(),
        provider: "bitbucket",
        hostURL: "https://bitbucket.org",
        providerUserID: "Trantienthanh2412",
        username: "Trantienthanh2412",
        scopes: ["read:repository:bitbucket", "write:repository:bitbucket"],
      },
    ));
  });

  test("Git provider metadata accepts HTTPS and SSH transport protocols", async () => {
    const userA = deviceContext("user-a");

    await assertSucceeds(setDoc(
      gitProviderAccount("user-a", "connection-https", userA),
      {
        ...validGitProviderAccount(),
        transportProtocol: "https",
      },
    ));
    await assertSucceeds(setDoc(
      gitProviderAccount("user-a", "connection-ssh", userA),
      {
        ...validGitProviderAccount(),
        transportProtocol: "ssh",
      },
    ));
  });

  test("a user can read and write only their own repository bookmarks", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
    const ownBookmark = repositoryBookmark("user-a", "bookmark-1", userA);

    await assertSucceeds(setDoc(ownBookmark, validRepositoryBookmark()));
    await assertSucceeds(getDoc(ownBookmark));
    await assertFails(getDoc(repositoryBookmark("user-a", "bookmark-1", userB)));
    await assertFails(setDoc(
      repositoryBookmark("user-a", "bookmark-1", userB),
      validRepositoryBookmark(),
    ));
    await assertSucceeds(deleteDoc(ownBookmark));
  });

  test("repository bookmarks reject local paths, secrets, and malformed metadata", async () => {
    const userA = deviceContext("user-a");
    const bookmark = repositoryBookmark("user-a", "bookmark-1", userA);

    for (const invalid of [
      { ...validRepositoryBookmark(), localPath: "/Users/test/Project/codex" },
      { ...validRepositoryBookmark(), accessToken: "must-not-be-stored" },
      { ...validRepositoryBookmark(), provider: "unknown" },
      { ...validRepositoryBookmark(), remoteURL: "file:///Users/test/codex" },
      { ...validRepositoryBookmark(), name: "" },
    ]) {
      await assertFails(setDoc(bookmark, invalid));
    }
  });

  test("a user can read and write only their own Git Flow configurations", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
    const ownConfiguration = gitFlowConfiguration("user-a", "repository-1", userA);

    await assertSucceeds(setDoc(ownConfiguration, validGitFlowConfiguration()));
    await assertSucceeds(getDoc(ownConfiguration));
    await assertFails(getDoc(gitFlowConfiguration("user-a", "repository-1", userB)));
    await assertFails(setDoc(
      gitFlowConfiguration("user-a", "repository-1", userB),
      validGitFlowConfiguration(),
    ));
    await assertFails(deleteDoc(ownConfiguration));
  });

  test("Git Flow configurations reject local state, unknown fields, and malformed values", async () => {
    const userA = deviceContext("user-a");
    const configuration = gitFlowConfiguration("user-a", "repository-1", userA);

    for (const invalid of [
      { ...validGitFlowConfiguration(), repositoryPath: "/Users/test/Project/codex" },
      { ...validGitFlowConfiguration(), recoveryCheckpoint: { phase: "primaryMerge" } },
      { ...validGitFlowConfiguration(), defaultStartDestination: "newWorktree" },
      { ...validGitFlowConfiguration(), accessToken: "must-not-be-stored" },
      { ...validGitFlowConfiguration(), schemaVersion: 2 },
      { ...validGitFlowConfiguration(), mainBranch: "" },
      { ...validGitFlowConfiguration(), topicFinishStrategy: "squash" },
      { ...validGitFlowConfiguration(), createReleaseTagOnFinish: "true" },
      { ...validGitFlowConfiguration(), updatedAt: "now" },
    ]) {
      await assertFails(setDoc(configuration, invalid));
    }
  });

  test("Git Flow configurations require every approved field", async () => {
    const userA = deviceContext("user-a");
    const configuration = gitFlowConfiguration("user-a", "repository-1", userA);

    for (const key of Object.keys(validGitFlowConfiguration())) {
      const missingField = validGitFlowConfiguration();
      delete missingField[key];
      await assertFails(setDoc(configuration, missingField));
    }
  });

  test("Git provider metadata rejects unsupported transport protocols", async () => {
    const userA = deviceContext("user-a");

    await assertFails(setDoc(
      gitProviderAccount("user-a", "connection-1", userA),
      {
        ...validGitProviderAccount(),
        transportProtocol: "token",
      },
    ));
  });

  test("clients cannot create update or delete entitlements", async () => {
    const userA = deviceContext("user-a");
    await assertFails(setDoc(entitlement("user-a", userA), { plan: "pro" }));

    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), { plan: "free" });
    });

    await assertFails(setDoc(entitlement("user-a", userA), { plan: "pro" }));
    await assertFails(deleteDoc(entitlement("user-a", userA)));
  });

  test("all clients can read but cannot write the release feature policy", async () => {
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(releaseFeaturePolicy(admin), {
        schemaVersion: 1,
        revision: 1,
        features: {},
      });
    });

    const userA = deviceContext("user-a");
    const guest = environment.unauthenticatedContext();

    await assertSucceeds(getDoc(releaseFeaturePolicy(userA)));
    await assertSucceeds(getDoc(releaseFeaturePolicy(guest)));
    await assertFails(setDoc(releaseFeaturePolicy(userA), { revision: 2 }));
    await assertFails(setDoc(releaseFeaturePolicy(guest), { revision: 2 }));
    await assertFails(deleteDoc(releaseFeaturePolicy(userA)));
  });

  test("unauthenticated clients are denied", async () => {
    const guest = environment.unauthenticatedContext();
    await assertFails(getDoc(settings("user-a", guest)));
    await assertFails(getDoc(entitlement("user-a", guest)));
  });

  test("plain Firebase sessions can access their own account cloud data", async () => {
    const plain = environment.authenticatedContext("user-a");
    await assertSucceeds(setDoc(settings("user-a", plain), validSettings()));
    await assertSucceeds(getDoc(settings("user-a", plain)));
  });

  test("Free accounts can claim one device but not two", async () => {
    const userA = deviceContext("user-a");
    const firstID = deviceIDs["user-a"];
    const secondID = "00000000-0000-4000-8000-000000000099";

    await assertSucceeds(setDoc(deviceSummary("user-a", userA), {
      schemaVersion: 1,
      activeDeviceIDs: [firstID],
      updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(setDoc(device("user-a", firstID, userA), validDeviceRecord()));
    await assertFails(setDoc(deviceSummary("user-a", userA), {
      schemaVersion: 1,
      activeDeviceIDs: [firstID, secondID],
      updatedAt: serverTimestamp(),
    }));
  });

  test("active Pro accounts can claim up to three devices", async () => {
    const userA = deviceContext("user-a");
    const ids = [
      deviceIDs["user-a"],
      "00000000-0000-4000-8000-000000000098",
      "00000000-0000-4000-8000-000000000099",
    ];
    await environment.withSecurityRulesDisabled(async (admin) => {
      await setDoc(entitlement("user-a", admin), { plan: "pro", access: "active" });
    });

    await assertSucceeds(setDoc(deviceSummary("user-a", userA), {
      schemaVersion: 1,
      activeDeviceIDs: ids,
      updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(deviceSummary("user-a", userA), {
      schemaVersion: 1,
      activeDeviceIDs: [...ids, "00000000-0000-4000-8000-000000000100"],
      updatedAt: serverTimestamp(),
    }));
  });

  test("device records are owner-scoped and schema validated", async () => {
    const userA = deviceContext("user-a");
    const userB = deviceContext("user-b");
    const ownDevice = device("user-a", deviceIDs["user-a"], userA);

    await assertSucceeds(setDoc(ownDevice, validDeviceRecord()));
    await assertSucceeds(getDoc(ownDevice));
    await assertFails(getDoc(device("user-a", deviceIDs["user-a"], userB)));
    await assertFails(setDoc(ownDevice, validDeviceRecord({ serial: "secret" })));
    await assertFails(deleteDoc(ownDevice));
  });
});


test("managed AI records and deletion fences deny all client access", async () => {
  const paths = ["aiState", "aiPeriods", "aiRequests", "aiRequestIDs", "aiOutbox"]
    .flatMap(collection => [`users/user-a/${collection}/record`, `users/user-a/${collection}/record/nested/record`]);
  paths.push("accountDeletionFences/user-a", "aiConfig/runtime", "aiJobs/periods");
  for (const context of [environment.authenticatedContext("user-a"), environment.authenticatedContext("user-b"), environment.unauthenticatedContext()]) {
    for (const path of paths) {
      const reference = doc(context.firestore(), path);
      await assertFails(getDoc(reference));
      await assertFails(setDoc(reference, { allowanceUnits: 500_000_000 }));
      await assertFails(deleteDoc(reference));
    }
  }
});
