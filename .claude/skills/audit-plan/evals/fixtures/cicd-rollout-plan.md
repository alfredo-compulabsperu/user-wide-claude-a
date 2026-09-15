# Rollout Plan: payments-api v2.14.0

## Preconditions (re-verified immediately before Step 1, not assumed from earlier in the week)

- Release Engineer runs the pre-flight check script, which re-confirms live:
  CI is green on `main` (unit + integration suites, coverage gate passing);
  staging deploy of the same build SHA has been running 24h with no new
  alerts; on-call engineer is confirmed and paged-in for the deploy window;
  `DATABASE_URL` secret for the payments read-replica resolves and a test
  connection succeeds. Step 1 does not start until this script exits 0.

## Steps

Each step has a single named owner (role, not a specific person, so the plan
survives on-call rotation).

1. **(Release Engineer)** Tag `v2.14.0` from the verified `main` SHA.
2. **(Release Engineer)** Deploy to canary (5% of traffic) via the standard
   blue/green pipeline.
3. **(Deploy pipeline, automated)** Watch the canary dashboard — error rate,
   p99 latency, **and payment-failure rate** — for 15 minutes. Auto-abort and
   revert canary traffic to 0% if error rate exceeds 1%, p99 exceeds 800ms,
   **or payment-failure rate exceeds its baseline threshold**; page the
   on-call engineer on any auto-abort with the triggering metric attached.
4. **(Release Engineer, with sign-off)** If canary is healthy, promote to
   100% traffic via the same pipeline — but only after the Release Engineer
   posts the canary metrics summary in the release channel and a second
   engineer (any engineer other than the releaser) explicitly approves the
   promotion there. The approval message is the logged sign-off; promotion
   does not fire on canary health alone.
5. **(Deploy pipeline, automated, with defined failure path)** Run the
   post-deploy smoke test suite against production immediately after full
   promotion. The suite exercises payment flows against a dedicated synthetic
   test-instrument account, never real customer payment data. **On any smoke
   suite failure, the pipeline automatically triggers the Rollback procedure
   below and pages on-call** — it does not merely report failure and wait.
6. **(Release Engineer)** Once the smoke suite passes, update the release
   notes and close the milestone.

## Rollback

- **Owner: on-call engineer for the deploy window** (same person named in
  Preconditions), whether rollback is triggered manually or by step 3/5's
  automated triggers.
- One-command rollback via the deploy pipeline's `rollback` action, which
  redeploys the previous tagged SHA and reverts traffic weighting to 0%
  immediately.
- `DATABASE_URL` is unchanged in this release, so no secret-side rollback
  action is needed this time. If a future release does ship a
  `DATABASE_URL` change, the standing procedure is: fetch the previous
  value from the secrets manager (never paste connection strings into chat
  or terminal history) and re-apply it through the same secrets-manager
  tooling used to provision it originally — the app-version rollback alone
  does not revert it.

## Verification

- Canary dashboard thresholds (error rate, p99, payment-failure rate) gate
  promotion automatically (step 3).
- A named second-engineer approval gates full promotion (step 4) —
  promotion is never fully automatic.
- Post-deploy smoke suite (step 5) is wired to auto-rollback on failure, not
  just a pass/fail report.
- Release is only marked done after the smoke suite passes post-promotion
  (step 6).
