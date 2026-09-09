---
name: pr-review
description: Review a pull request or diff by classifying each changed area into its review domain (data migration, API/schema contract, infra/config, application code, LLM/agent artifact, docs), deferring to that domain's own dedicated skill/rule/agent where the repo has one, and applying cross-cutting sequencing, evidence, and scope discipline throughout. Findings are always reported in the conversation; pass --comment to also post them to the PR. Use whenever asked to review, approve, give feedback on, or assess a PR/diff/branch. Do not use for merging, fixing, or closing a PR — those are separate actions.
---

# PR Review

A PR review holds two lenses at once: **author-intent** ("does this do what it claims")
and **reviewer-skepticism** ("what would make this wrong that the diff doesn't show").
Intent-only is a rubber stamp; skepticism-only is obstruction. There is no such thing as
a perfect PR — approve once it improves the target repo's correctness/health, not once
every possible nit is resolved. Reserve blocking status for Step 3's first two questions
(correct-and-safe, still-belongs); style and taste findings are non-blocking by default.

This skill is repo-agnostic and deliberately thin: it owns the cross-cutting mechanics of
*how* to sequence and conduct a review, not the domain-specific *what to check*. Domain
knowledge (how to review a migration, a Terraform plan, a docs page) belongs to whichever
skill, rule, or agent already owns that domain in the target repo — restating it here
would duplicate and eventually drift from that source, the same failure mode as any other
un-DRY rule duplication. A compact fallback appendix exists below for domains the repo
has no dedicated owner for.

## Step 0 — Pre-flight gates

**Re-validation (MUST, immediately before approval).** A clean auto-merge against the
current target base is not proof of correctness. Confirm:
- The PR is actually up to date with its current base branch — not just "no conflict
  markers."
- Its checks/tests/gates were **re-run after that merge**, not only at PR-open time.

If this hasn't happened, that's the review's first finding, not something to route
around. This is a MUST at the merge gate specifically, not a demand to re-merge on every
base-branch commit during a long-lived PR's life — treat continuous re-merging as a
SHOULD, the check right before landing as the hard MUST.

**Responsiveness check (SHOULD, for large or multi-round PRs).** Before investing deep
review time, check the PR's history: has it engaged with prior feedback, or gone quiet
after previous rounds? Does a large/complex change have a stated implementation plan, or
did it just arrive as a diff? If there's no plan and no responsiveness track record,
request a plan before reviewing deeper rather than sinking another round into it.

## Step 1 — Classify into review domains, then defer to the domain's own owner

One PR can span multiple review domains. For each one present:

| Review domain | Review artifact of record (what you actually inspect, not the diff) |
|---|---|
| Data migration | the rollback/recovery plan, read *before* the schema diff |
| API / schema contract | the compatibility diff (old vs. new spec), classified breaking/potentially-breaking/silently-breaking |
| Infra / config (IaC, k8s, CI) | the plan / diff-of-effect output |
| Application code / scripts | the diff, read in dependency order (foundational files before callers) |
| LLM / agent artifact (`.claude/**`, system prompts, agents, skills, hooks) | a behavioral comparison — what this causes to happen differently |
| Docs | the rendered page + the procedure actually run, checked against the already-reviewed code/contract |

**For each domain touched:** check whether the target repo already has a skill, agent, or
rule dedicated to it (a migrations-review skill, a Terraform/IaC skill, a docs style
guide, a security-review agent, a rule governing agent artifacts, etc.). If one exists,
apply its criteria and **cite it explicitly in your findings** rather than presenting its
guidance as your own judgment call — do not restate its content here, and do not let this
skill's generic guidance override a more specific one the repo already committed to. Only
fall back to the Appendix below when no domain owner exists.

**If more than one owner exists for the same domain:** prefer the narrowest-scoped match
over a general one (a dedicated migrations skill outranks a general code-review skill
that happens to mention migrations in passing). Apply multiple owners together when they
cover disjoint sub-concerns. If two owners genuinely conflict on the same check, don't
silently pick one — report the conflict itself as a finding ("this repo has inconsistent
review guidance for this domain"), the same evidence-discipline principle as Step 4:
manufactured confidence is worse than a stated gap.

## Step 2 — Sequence a multi-domain PR

Blast-radius-first and dependency-order-first point the same direction here, because the
upstream layers usually carry both the highest correctness-dependency and the highest,
least-reversible risk:

1. **Data migrations** — first, separately if at all possible; request a split if bundled
   with feature code.
2. **API/schema contracts** — next; they define what every downstream layer may assume.
3. **Infra/IaC** — via plan output, destructive/permission changes first.
4. **Application code and scripts** — dependency order.
5. **LLM/agent artifacts** — behavioral-diff discipline.
6. **Docs** — last; by the time you reach them the behavior they describe is settled, so
   checking them against it is cheap and unambiguous instead of guesswork.

## Step 3 — Three questions, in order of blast radius

1. **Correct and safe** — does it do what it claims, without the domain's specific
   failure mode (see the domain owner or Appendix)?
2. **Still belongs** — is it stale, does it duplicate or regress something the base
   branch picked up since the branch was cut? Most review processes skip this entirely —
   a PR correct-when-written and now redundant or wrong isn't a correctness bug, it's a
   currency bug, and only this question (plus Step 0) catches it.
3. **Minimal and honest** — no unverified self-report standing in for evidence (see
   Step 4); scope stays tight (see Step 5).

## Step 4 — Evidence discipline

When a doubt is raised, resolve it with a check — diff the bytes, grep for the reference,
run the thing — not a restated assertion. "I read the diff and it looks right" is not
evidence. If a check isn't cheaply available, say the doubt is unresolved rather than
asserting confidence you don't have.

For genuinely ambiguous go/no-go calls, get more than one independent perspective before
deciding; treat convergence across independent voices as a real signal.

## Step 5 — Scope discipline

One topic per PR. A PR bundling unrelated concerns is a signal to request a split, not a
reason to review each concern at lower rigor because any one piece is small.

## Output

Label each finding using the Conventional Comments standard (conventionalcomments.org):
`praise` / `nitpick` / `suggestion` / `issue` / `todo` / `question` / `thought` / `chore`
/ `note`, decorated `(blocking)` / `(non-blocking)` / `(if-minor)` where useful — richer
than a binary blocks-merge flag, which loses the distinction between "must fix" and
"worth mentioning," and gives the author something to act on directly rather than a label
invented per-review. Leave at least one genuine `praise` when one is earned; don't
manufacture false praise to check a box.

State each finding as: which step it came from, the specific evidence, and its label.
Don't bury a Step 3.2 (staleness) finding under Step 3.1 (correctness) findings — they
point at different fixes.

Frame every finding at the code, not the person — "we should add tests for this," not
"you forgot tests." The distinction isn't cosmetic: it's the difference between a review
that reads as collaborative and one that reads as gatekeeping, and it costs nothing to
get right.

**Findings are always reported in the conversation.** Posting them to the PR itself is
opt-in: pass `--comment` to also post — inline, anchored to the specific file/line, for
findings the review surface can anchor that way; one structured comment for findings that
don't anchor to a single line (e.g. a Step 3.2 staleness finding about the PR as a whole)
or when the surface doesn't support inline comments. Without `--comment`, nothing is
posted anywhere — the conversation output is the only artifact. Use whatever
inline-comment mechanism the review surface actually provides; don't hardcode a specific
host's CLI or API here, since this skill is repo- and host-agnostic.

## Scope and boundaries

- **Tool selection (MUST).** If the repo has its own explicit PR-review tool — a
  repo-local command, skill, or agent whose stated purpose is reviewing a PR/diff as a
  whole, not a generic linter or single-dimension quality tool — do not silently pick
  one. Compare what each covers and which fits the diff at hand, then prompt the user to
  choose between the repo-local tool and this skill, stating a recommendation. If the repo
  has no such tool, use this skill directly and do not ask. A plan step that names this
  choice must not lock it in at authoring time — name no tool, or state the choice is
  deferred to execution, since repo tooling can change before the step runs.
- Review only — not merge/fix/close.
- Repo-agnostic — no hardcoded paths; identify the repo's own canonical/high-stakes files
  and domain-owner skills fresh each time.
- Not a CI substitute — this exists for what automation structurally can't catch:
  staleness, business-logic correctness, and the domains above with no test suite.

---

## Appendix — fallback domain notes (use only when the repo has no dedicated owner)

**Data migrations:** invert the size heuristic — a small diff isn't a safe one. Ship
alone. Reversibility must be a declared decision, not an omission. Lock behavior doesn't
show in the diff — need `lock_timeout`/`statement_timeout` and real table size. Expand →
dual-write → backfill → switch → contract keeps every intermediate state safe. Backfills
are their own reviewable unit: batched, idempotent, throttled. "Tested on empty dev DB"
is not tested. Require the PR description to state, explicitly: the down-migration or
recovery path, the feature-flag/code gate controlling the new path, how a backfill would
be reversed, and the measured lock window — treat a missing one of these as a finding,
not an assumption.

**API/schema contracts:** classify breaking/potentially-breaking/silently-breaking before
reviewing anything built on the contract. Don't trust a tool's "non-breaking" label on
nullability or enum changes — a naive client still breaks. This belongs in CI as a gate.
For a shared or public contract, prefer consumer-driven verification (each real consumer
states what it actually reads/handles, checked in CI) over trusting the spec diff alone —
the spec can be technically compatible while breaking a consumer's undocumented
assumption. Before approving a breaking change, confirm it went through an explicit
versioning decision (additive-only vs. needs-a-version-boundary vs. immediately-breaking)
rather than being decided implicitly by whoever wrote the diff.

**Infra/config:** diff shows intent, plan shows effect — never approve on the diff alone.
Blast radius, not diff size — a 3-line shared-template change can hit every environment.

**Application code:** style is automatable, never a manual blocker. PR size predicts
defect-detection failure — flag for splitting past ~400 lines rather than reviewing at
full rigor. For agent-authored PRs: check whether CI was weakened, code was duplicated
instead of reused, or tests pass while the logic is wrong — trace the most critical path
end to end rather than skimming the whole diff. When no other pacing guidance exists, a
reasonable default for a sub-400-line PR: classify and scan for CI/test weakening first,
scan for duplicated utilities second, trace one critical path third, security boundaries
fourth, require evidence for non-trivial claims last.

**LLM/agent artifacts:** text distance and behavioral distance are nearly uncorrelated —
judge by effect, not wording. Ask per changed instruction: what does it assert, what
failure was it added to prevent, what new failure could changing it enable. Also check:
did anything change position in the prompt/instructions (early instructions anchor
interpretation more than late ones); do any two instructions now conflict under some
input; if the artifact relies on examples, were any added, removed, or reordered
(examples often carry more behavioral weight than prose instructions). Check whether a
hook change fails open (dangerous) or closed. Triggering conditions, concretely: did the
artifact's description or invocation trigger phrases change in a way that makes it fire
more or less often than intended — over-triggering and under-triggering are both invisible
in a text diff and only show up in actual invocation. Injection surface, concretely: is
untrusted PR/issue/commit-message text interpolated into a prompt without sanitization;
is a token/credential scoped to write when only read is needed; is model output executed
as a shell command or tool call without validation. No deploy step between merge and
effect — blast radius is immediate and session-wide.

**Docs:** run the procedure the page describes, in the environment it promises, not just
read the source markdown. Accuracy, structure, and currency are three different
competencies — a subject-matter check ("is this still true"), an editorial check ("is
this clear"), and a currency check ("is this the right version") are different jobs;
don't let one sign-off silently cover all three.
