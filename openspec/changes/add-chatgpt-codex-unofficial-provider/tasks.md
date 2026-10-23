# Tasks

## 1. Verify the Codex flow

- [ ] 1.1 Recheck the authorize, token, revoke, and backend values and the dialect differences in design.md against the current TablePro source and Codex CLI source. Record the usage-limit and plan error codes in design.md, and verify that `openspec validate add-chatgpt-codex-unofficial-provider` passes.

## 2. Session and transport

- [ ] 2.1 Generalize `ChatGPTAccountSession` with a flow descriptor:
  - official flow: dynamic registration and the plan-scope check;
  - Codex flow: fixed client ID, no nonce, account ID and plan type from claims, separate Keychain accounts.

  Verify that the existing `ChatGPTAccountSessionTests` pass unchanged and that new Codex cases pass: authorize URL, code exchange without a nonce, missing account ID rejected, refresh with `scope`, and tokens kept separate from the official store.
- [ ] 2.2 Let `ChatGPTLoopbackCallbackServer` take a required port and a redirect host. Verify with a test that a Codex sign-in fails clearly when port 1455 is taken, and that the official provider still falls back to a free port.
- [ ] 2.3 Add the `.codexBackend` dialect to `OpenAIResponsesClient`:
  - headers;
  - no `max_output_tokens`;
  - reasoning `summary`;
  - tool-call arguments from `output_item.done`.

  Verify with `ChatGPTCodexProviderTests` request-encoding and SSE-parsing cases. Verify that `ChatGPTSubscriptionProviderTests` and `CloudAIProviderTests` still pass.

## 3. Provider

- [ ] 3.1 Add `AIProviderID.chatGPTCodex`, the descriptor (`isUnofficial`, `.connectedAccount`, Pro-gated), the curated models, and `ChatGPTCodexProvider`. Register it in `AIProviderRegistry.live`. Verify the registry-order test in `AICommitMessageTests`.
- [ ] 3.2 Map Codex backend errors to `codexSignInRequired`, `codexUsageLimitReached`, `codexPlanNotAllowed`, and `codexClientRejected`, with no fallback. Verify with `ChatGPTCodexProviderTests` cases covering 401, 429, 403, and a blocked client.

## 4. Controller and Settings UI

- [ ] 4.1 Generalize the `AIProviderController` ChatGPT sign-in, timeout, Copy Link, disconnect, and model refresh to take the provider ID, and add the local risk-acknowledgment flag. Verify with `CloudAIProviderTests`:
  - the three providers stay independent;
  - disconnecting falls back to Apple Intelligence;
  - sign-in is refused before acknowledgment.
- [ ] 4.2 Add the Codex sheet section:
  - the "Unofficial" label;
  - the acknowledgment notice that gates the sign-in button;
  - email and plan type;
  - waiting state with link, Copy Link, and Cancel;
  - Disconnect.

  Also show the badge in the provider list and the menu. Verify that the app builds.
- [ ] 4.3 Verify the Pro gate in `CommitPlusAISelectionPolicyTests`: a Free Commit+ user cannot sign in, a lapsed Pro user can disconnect, and the policy-unavailable fallback works.

## 5. Validation

- [ ] 5.1 Run `ChatGPTAccountSessionTests`, `ChatGPTSubscriptionProviderTests`, `ChatGPTCodexProviderTests`, `CloudAIProviderTests`, `CommitPlusAISelectionPolicyTests`, and `AICommitMessageTests` sequentially, then run `git diff --check`.
- [ ] 5.2 Manually review Settings → AI with a real ChatGPT Free account:
  - acknowledgment, sign-in, and the plan shown;
  - Copy Link;
  - commit-message generation and an agent mutation with confirmation;
  - disconnect;
  - the official ChatGPT and OpenAI providers unaffected.
- [ ] 5.3 After a real sign-in and request, confirm that no Codex token appears in logs or in `CloudSettingsDocument`.

## Workflow follow-up

- Land `add-chatgpt-subscription-provider` before applying this change.
- Archive after the manual review passes.
