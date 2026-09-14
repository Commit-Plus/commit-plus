import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();

const polarAccessToken = defineSecret("POLAR_ACCESS_TOKEN");
const polarServer = defineString("POLAR_SERVER", { default: "sandbox" });

export interface WebSignInTokenDependencies {
  createCustomToken(uid: string): Promise<string>;
}

function webSignInTokenDependencies(): WebSignInTokenDependencies {
  return {
    createCustomToken: (uid) => getAuth().createCustomToken(uid),
  };
}

export async function createWebSignInTokenForUser(
  uid: string,
  dependencies: WebSignInTokenDependencies = webSignInTokenDependencies(),
): Promise<string> {
  return dependencies.createCustomToken(uid);
}

export const createWebSignInToken = onCall({ invoker: "public" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before opening Commit+ on the web.");
  }

  return { customToken: await createWebSignInTokenForUser(uid) };
});

export interface AccountDeletionDependencies {
  beginDeletion(uid: string): Promise<void>;
  deletePolarCustomer(uid: string, verifiedEmail?: string): Promise<void>;
  deleteDocument(path: string): Promise<void>;
  deleteCollection(path: string): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

export async function deleteOwnedCollection(path: string): Promise<void> {
  const firestore = getFirestore();
  await firestore.recursiveDelete(firestore.collection(path));
}

function productionDependencies(): AccountDeletionDependencies {
  return {
    beginDeletion: async (uid) => {
      // Retain this minimal tombstone: delayed billing events and workers must stay fenced.
      await getFirestore().doc(`accountDeletionFences/${uid}`).set({ deleting: true });
    },
    deletePolarCustomer: async (uid, verifiedEmail) => {
      const apiURL = polarServer.value() === "production"
        ? "https://api.polar.sh"
        : "https://sandbox-api.polar.sh";
      const headers = {
        Authorization: `Bearer ${polarAccessToken.value()}`,
        Accept: "application/json",
      };
      let response = await fetch(
        `${apiURL}/v1/customers/external/${encodeURIComponent(uid)}?anonymize=true`,
        {
          method: "DELETE",
          headers,
        },
      );

      if (response.ok) return;
      if (response.status !== 404) {
        throw new Error(`Polar customer deletion failed with status ${response.status}.`);
      }
      if (!verifiedEmail) return;

      const customersURL = new URL(`${apiURL}/v1/customers/`);
      customersURL.searchParams.set("email", verifiedEmail);
      customersURL.searchParams.set("limit", "10");
      response = await fetch(customersURL, { headers });
      if (!response.ok) {
        throw new Error(`Polar customer lookup failed with status ${response.status}.`);
      }

      const payload = await response.json() as {
        items?: Array<{ id: string; email: string; external_id?: string | null }>;
      };
      const normalizedEmail = verifiedEmail.trim().toLowerCase();
      const matches = (payload.items ?? []).filter(
        (customer) => customer.email.trim().toLowerCase() === normalizedEmail,
      );
      if (matches.length > 1) {
        throw new Error("Multiple Polar customers match this Firebase account email.");
      }

      const customer = matches[0];
      if (!customer) return;
      if (customer.external_id && customer.external_id !== uid) {
        throw new Error("The Polar customer belongs to a different Firebase account.");
      }

      response = await fetch(
        `${apiURL}/v1/customers/${encodeURIComponent(customer.id)}?anonymize=true`,
        { method: "DELETE", headers },
      );
      if (!response.ok && response.status !== 404) {
        throw new Error(`Polar customer deletion failed with status ${response.status}.`);
      }
    },
    deleteDocument: async (path) => {
      await getFirestore().doc(path).delete();
    },
    deleteCollection: deleteOwnedCollection,
    deleteUser: (uid) => getAuth().deleteUser(uid),
  };
}

export async function deleteAccountData(
  uid: string,
  dependencies: AccountDeletionDependencies = productionDependencies(),
  verifiedEmail?: string,
): Promise<void> {
  await dependencies.beginDeletion(uid);
  await dependencies.deletePolarCustomer(uid, verifiedEmail);

  await Promise.all([
    ...["aiState", "aiPeriods", "aiRequests", "aiRequestIDs", "aiOutbox"].map(
      (collection) => dependencies.deleteCollection(`users/${uid}/${collection}`),
    ),
    dependencies.deleteCollection(`users/${uid}/devices`),
    dependencies.deleteCollection(`users/${uid}/gitProviderAccounts`),
    dependencies.deleteCollection(`users/${uid}/repositoryBookmarks`),
    dependencies.deleteCollection(`users/${uid}/gitFlowConfigurations`),
    dependencies.deleteDocument(`users/${uid}/deviceAccess/summary`),
  ]);

  await Promise.all([
    dependencies.deleteDocument(`users/${uid}/settings/app`),
    dependencies.deleteDocument(`entitlements/${uid}`),
  ]);

  try {
    await dependencies.deleteUser(uid);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code !== "auth/user-not-found") throw error;
  }
}

export const deleteAccount = onCall({ secrets: [polarAccessToken] }, async (request) => {
  const authenticatedUser = request.auth;
  if (!authenticatedUser) {
    throw new HttpsError("unauthenticated", "Sign in again before deleting the account.");
  }
  const uid = authenticatedUser.uid;

  const authTime = Number(authenticatedUser.token.auth_time ?? 0);
  if (Math.floor(Date.now() / 1000) - authTime > 300) {
    throw new HttpsError("failed-precondition", "Recent authentication is required.");
  }

  const verifiedEmail = authenticatedUser.token.email_verified === true &&
      typeof authenticatedUser.token.email === "string"
    ? authenticatedUser.token.email
    : undefined;
  await deleteAccountData(uid, productionDependencies(), verifiedEmail);
  return { deleted: true };
});
