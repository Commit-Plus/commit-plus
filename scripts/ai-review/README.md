# AI PR review

Reviews non-draft PRs targeting `main` before merging. Updates one advisory PR
comment on each head change. It does not approve PRs or block merging on findings
or provider outages. GitHub API errors still fail the job so delivery failures
remain visible. Do not make this workflow a required branch-protection check.

Add repository Actions secrets (any missing provider is skipped):

- `OPENROUTER_API_KEY`
- `GROQ_API_KEY`
- `DEEPSEEK_API_KEY`

Provider order is OpenRouter → Groq → DeepSeek. Any HTTP error (including quota,
rate limits, authentication and model errors), timeout, malformed, empty or
truncated response advances to the next provider, once per provider. If all fail,
the comment explicitly reports that no review completed. Each call times out
after 75 seconds; there are no repeated quota retries.

Defaults: `openrouter/free`, `openai/gpt-oss-120b`, `deepseek-flash`.
Optional repository variables `AI_REVIEW_OPENROUTER_MODEL`,
`AI_REVIEW_GROQ_MODEL`, `AI_REVIEW_DEEPSEEK_MODEL` override these.
OpenRouter's free router selects available free models; quality can vary.
Groq usage depends on your account plan. DeepSeek is a paid final fallback;
omit its secret to keep it disabled. Configure billing limits at the providers.

Uses `pull_request_target` to support fork PRs with repository secrets. Only
the trusted base commit is checked out, credentials are not persisted, and PR
code is never executed. The PR diff is sent to external providers, including
for fork PRs; consider their data policies for private code. No tools or repository
write operations are available to the model. Reviews only the first 24,000
characters and labels truncated inputs as partial. Diff context is limited;
this does not replace human review or builds.

The workflow and script must land on `main` before it can review subsequent PRs.
No app build is needed for these CI-only files.

Set secrets interactively without putting keys into shell history:

```sh
gh secret set OPENROUTER_API_KEY
gh secret set GROQ_API_KEY
gh secret set DEEPSEEK_API_KEY
```

Sources:
- https://openrouter.ai/openrouter/free
- https://console.groq.com/docs/models
- https://console.groq.com/docs/rate-limits
- https://api-docs.deepseek.com/quick_start/pricing/
