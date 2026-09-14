import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { getFirestore } = require('firebase-admin/firestore');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') throw new Error('Local Firestore emulator required');
process.env.GCLOUD_PROJECT = 'demo-commit-plus-ai';
const { deleteAccountData, deleteOwnedCollection } = await import('../functions/lib/index.js');
test('account deletion recursively removes nested AI records while retaining its fence', async () => {
  const db = getFirestore(), uid = 'ai-deletion-test';
  const collections = ['aiState', 'aiPeriods', 'aiRequests', 'aiRequestIDs', 'aiOutbox'];
  const paths = collections.flatMap(name => [`users/${uid}/${name}/record`, `users/${uid}/${name}/record/nested/record`]);
  for (const path of paths) await db.doc(path).set({ test: true });
  await deleteAccountData(uid, {
    beginDeletion: async () => { await db.doc(`accountDeletionFences/${uid}`).set({ deleting: true }); },
    deletePolarCustomer: async () => { assert.equal((await db.doc(`accountDeletionFences/${uid}`).get()).exists, true); },
    deleteDocument: async path => { await db.doc(path).delete(); },
    deleteCollection: deleteOwnedCollection,
    deleteUser: async () => {},
  });
  for (const path of paths) assert.equal((await db.doc(path).get()).exists, false);
  assert.equal((await db.doc(`accountDeletionFences/${uid}`).get()).exists, true);
  await db.terminate();
});
