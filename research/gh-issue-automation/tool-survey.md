# GitHub Issue Triage & Autonomous Work: Tool Survey

> **Última actualización:** 2026-06-30 (v1.1 — ECC Tools POC result added)

## Executive Summary

For a single-developer personal repo with no existing CI/CD that wants to autonomously implement issue work via Claude Code (`claude -p`) and open PRs, **GitHub Actions + `claude-code-action`** is the clear winner. It integrates natively with GitHub's event system (no custom server, no persistent infrastructure), fires on `issues: types: [opened]` for a fully autonomous trigger (no human touch required after issue creation), can autonomously create branches and implement code changes from moderate complexity, and is free for public repos — with only Anthropic API token costs (no flat fee). Probot is the next most capable option but requires writing and deploying a persistent Node.js app, adding significant setup and maintenance burden for a solo developer. n8n offers a self-hosted free Community Edition but its GitHub integration is connector-based, not native App-level. Raw webhooks + custom server and bare GitHub Apps offer maximum flexibility but maximum operational cost.

**ECC Tools GitHub App** (`github.com/apps/ecc-tools`) is a complementary prerequisite, not an alternative: confirmed via live POC test (2026-06-30) that `/ecc-tools analyze` generates harness configuration artifacts (skills, rules, hooks, identity manifest) — not feature implementation code. Run it once to bootstrap `.claude/` artifacts into the repo; those committed artifacts are then available to any Actions runner that clones the repo.

---

## Ranking Table

| Tool | Popularity | Maturity | Setup Complexity | Maint. Burden | GitHub Depth | Cost | **Score** |
|------|-----------|----------|-----------------|---------------|-------------|------|-----------|
| **GitHub Actions + claude-code-action** | High | v1.0 (Sep 2025), active | Low — 1 YAML file + 1 secret | Very Low | Native (App: R/W issues, PRs, labels) | Free (public repo) + API tokens | **1st** |
| **ECC Tools GitHub App** | N/A | Active (2026) | Very Low — install App + comment `/ecc-tools analyze` | Very Low | Native (issues: write, contents: write, PRs: write) | Free (public repos, 10 analyses/mo) | **Prerequisite** |
| **Probot** | Moderate (9.6k ★) | High (v14.x, 2026 releases) | High — Node.js app + hosting | Medium | Native (Octokit, full REST/GraphQL) | Free framework; hosting costs | **2nd** |
| **n8n** | Very High (194k ★) | High | Medium (self-host) / Low (cloud) | Low (cloud) / Medium (self-host) | Connector-based (not native App) | €0 self-host / €20+/mo cloud | **3rd** |
| **GitHub Apps (custom)** | N/A | Very High | Very High — register App, implement webhook handler | High | Full native (same as Probot) | Free API; hosting costs | **4th** |
| **Webhooks + custom server** | N/A | High | Very High — HTTP server + ngrok or hosting | High | Full native (via REST/GraphQL) | Hosting costs | **5th** |

---

## Finding 1 — GitHub Actions + `claude-code-action`: Best Fit for Autonomous Issue Work

**Trigger support (native, no custom code required):**
- The action listens on `issues: types: [opened, assigned, labeled]` — the exact workflow described in the goal.[^1]
- Assignment-based trigger: `assignee_trigger` input parameter activates Claude when a specific GitHub user (e.g., `@claude`) is assigned to an issue, without requiring an `@claude` mention in a comment.[^2]
- Label-based trigger: `label_trigger` input (default: `"claude"`) fires when that label is applied to an issue.[^1]

**Autonomous implementation capability:**
- The action can implement code changes from simple fixes to refactoring and new features — not just answer questions.[^3]
- Confirmed workflow: `@claude mention or trigger → Claude creates branch → implements feature → opens PR`.[^3]
- Limitations: complex multi-file architectures and ambiguous requirements are outside reliable scope.

**Setup complexity:**
- Workflow file at `.github/workflows/claude.yml` + one repository secret (`ANTHROPIC_API_KEY`).
- The official `examples/claude.yml` is the starting template; `label_trigger` and `assignee_trigger` inputs are drop-in.
- ⚠️ verify: Exact permission scope for the bundled GitHub App (especially label write access) should be confirmed against current App settings at code.claude.com.

**Cost:**
- GitHub Actions minutes: **free for public repositories** (no per-minute charge on standard runners).[^4]
- Private repos: 2,000 free minutes/month on GitHub Free plan; 3,000 on Pro/Team.[^5]
- Anthropic API: pay-per-token on each invocation — scales with prompt length and codebase size. No flat fee.
- ECC Tools pricing page (`ecc.tools/pricing`) covers a separate code-analysis SaaS; no harness-level `claude -p` billing data found there.[^6]

---

## Finding 2 — ECC Tools GitHub App: Harness Bootstrap, Not Issue Worker

**Scope confirmed via live POC (2026-06-30):**[^15]
- POC repo: `alfredo-compulabsperu/ecc-tools-poc` — single bash script, one feature-request issue
- Trigger: commented `/ecc-tools analyze` on issue #1 (feat: add --name flag)
- Result: ECC Tools opened PR #2 titled "feat: add ecc-tools-poc ECC bundle" within 2 minutes
- PR contents: `.claude/skills/`, `.claude/ecc-tools.json`, `.claude/identity.json`, `.claude/homunculus/instincts/`, `.agents/skills/`, `.codex/` config files
- `scripts/greet.sh` was **not touched** — the feature request was ignored entirely

**What ECC Tools does:**
- Analyzes git history, architecture, and workflow patterns
- Generates harness artifacts: repo-specific skills, identity baseline, continuous-learning instincts, Codex config
- Opens a PR with those artifacts; human merges to commit them to the repo
- Commands: `/ecc-tools analyze`, `/ecc-tools setup`, `/ecc-tools audit`, `/ecc-tools doctor`, `/ecc-tools repair` — all config lifecycle, not feature implementation

**Why it matters for issue #12:**
- Solves the "harness in cloud" problem: run ECC Tools once → merge PR → `.claude/` artifacts are committed → available to any Actions runner that clones the repo
- Does NOT replace `claude-code-action`; is a one-time setup step before enabling the autonomous worker

**Cost:** Free for public repos (10 analyses/month, up to 200 commits/run). Pro at $19/seat/month for private repos.[^16]

---

## Finding 3 — Probot: Most Mature Alternative, High Setup Cost for Solo Dev

**Community and maturity:**
- 9,568 GitHub stars, 1,036 forks, 901 public repos tagged `probot`.[^7][^8]
- 51,552 npm downloads/week (week ending 2026-06-28).[^9]
- Actively maintained: v14.3.2 released 2026-04-03; three releases in March–April 2026.[^10]
- Node.js/TypeScript framework — not a hosted no-code service.[^11]

**GitHub integration depth:**
- Full native access: `app.on()` / `app.onAny()` listen to any GitHub webhook event; `context.octokit` provides authenticated REST + GraphQL client.[^12]
- Covers issues, comments, labels, and PRs natively. Minor caveat: a small number of GitHub App API endpoints remain unsupported.[^12]

**Setup complexity for single-developer personal repo:**
- Requires writing custom Node.js code and deploying infrastructure (persistent server or serverless adapter).
- Deployment options: always-on server, AWS Lambda, Vercel, Google Cloud Functions (official adapters exist).
- **Not recommended** for this use case: development + deployment overhead outweighs the benefit vs. a YAML-first Actions approach.

---

## Finding 3 — n8n: Good for General Automation, Weaker GitHub Depth

**Deployment and cost:**
- **Self-hosted Community Edition**: free (MIT-style Sustainable Use License; royalty-free for personal use), distributed via GitHub (194k ★).[^13]
- **Cloud Starter plan**: €20/month (billed annually), 2,500 workflow executions/month, no permanent free cloud tier (trial available).[^14]

**GitHub integration:**
- Connector-based (pre-built nodes), not a native GitHub App with App-level permissions.
- Can read/write issues and trigger webhooks but lacks the deep App-level context that Probot or claude-code-action carry.
- Would require a separate mechanism to invoke `claude -p`; not a drop-in solution for autonomous coding.

---

## Finding 4 — GitHub Actions Pricing (Context for Runner Costs)

| Plan | Free minutes/month | Public repo runners |
|------|-------------------|---------------------|
| GitHub Free | 2,000 | Free (no charge) |
| GitHub Pro | 3,000 | Free (no charge) |
| GitHub Team | 3,000 | Free (no charge) |
| GitHub Enterprise Cloud | 50,000 | Free (no charge) |

Standard GitHub-hosted runners incur **no per-minute charges on public repositories**.[^4][^5] The 2026 Actions pricing overhaul (effective Jan/Mar 2026) preserved free minute quotas and reduced per-minute costs for private-repo overage.[^5]

---

## Caveats

- **ECC harness pricing**: `ecc.tools/pricing` describes a code-analysis SaaS (Free/Pro/Enterprise tiers at $0–$19/seat/month), not a harness for billing `claude -p` invocations. No per-invocation ECC billing data was found. ⚠️ verify: contact ECC directly for harness billing if that matters.
- **claude-code-action label_trigger bug**: An open issue (#210) documents a bug with `label_trigger` in the action; `assignee_trigger` is unaffected. Test label triggering on a fork before relying on it in production.
- **Anthropic API cost unpredictability**: Token cost per issue scales with repo size and prompt complexity; no public per-issue benchmark exists for typical PRs.
- **Refuted setup claim**: The claim that setup requires "only two steps" (YAML + one secret, no other configuration) was refuted (0-3 vote) — actual setup involves GitHub App installation and permission configuration beyond a single secret.
- **n8n license**: The Sustainable Use License is not OSI-approved open source; it prohibits commercial redistribution. Personal use is explicitly permitted at no cost.

---

## Open Questions

1. **What is the actual Anthropic API cost per autonomous issue-to-PR invocation?** No public benchmark exists for typical codebase sizes and issue complexity.
2. **Does the `label_trigger` bug (issue #210) affect the `issues: labeled` GitHub event, or only the action's internal `label_trigger` input parameter?** The distinction matters for which trigger strategy to use.
3. **Can `claude-code-action` be configured to use a locally-installed `claude -p` on a self-hosted runner instead of the bundled CLI, enabling ECC harness usage?** If so, ECC's harness billing model would apply.
4. **Are there meaningful differences between using `anthropic/claude-code-action` vs. invoking `claude -p` directly in a `run:` step?** The former bundles GitHub App context; the latter offers more scripting control but requires manual git operations.

### Closed Questions

~~**Can ECC Tools generate feature implementation code from issues, or is it config-only?**~~
**CLOSED — config-only (confirmed).** Live POC 2026-06-30: `/ecc-tools analyze` on a feature-request issue opened a PR with harness artifacts only (skills, identity, instincts, Codex config). Feature code was not touched. ECC Tools is a harness bootstrap tool, not an issue worker.[^15]

~~**Does the `issues: types: [opened]` trigger require human action?**~~
**CLOSED — no human action required.** `on: issues: types: [opened]` fires automatically on issue creation. The `label_trigger` and `assignee_trigger` inputs are the *selective* path (human must apply label/assignment). For a fully autonomous worker, use `opened`.

---

[^1]: `issues: types: [labeled]` trigger and `label_trigger` input. anthropics/claude-code-action — action.yml, src/github/validation/trigger.ts, docs/usage.md. https://github.com/anthropics/claude-code-action (2026-06-30)
[^2]: Assignment trigger. anthropics/claude-code-action — action.yml `assignee_trigger` input; docs/usage.md. https://github.com/marketplace/actions/claude-code-action-official (2026-06-30)
[^3]: Autonomous implementation capability. Anthropic GitHub Marketplace listing + capabilities-and-limitations.md. https://github.com/marketplace/actions/claude-code-action-official (2026-06-30)
[^4]: Public repo runners are free. GitHub Docs — About billing for GitHub Actions. https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions (2026-06-30)
[^5]: Free monthly minute quotas by plan. GitHub Docs — billing reference. https://docs.github.com/en/billing/reference/product-usage-included (2026-06-30)
[^6]: ECC Tools pricing. https://ecc.tools/pricing (2026-06-30)
[^7]: Probot stars and forks. GitHub API — probot/probot. https://github.com/probot/probot (2026-06-29)
[^8]: Probot topic repository count. https://github.com/topics/probot (2026-06-30)
[^9]: Probot npm weekly downloads. https://www.npmjs.com/package/probot (week ending 2026-06-28)
[^10]: Probot release history. https://github.com/probot/probot/releases (2026-06-30)
[^11]: Probot is a Node.js/TypeScript framework, not a hosted service. https://github.com/probot/probot — README (2026-06-30)
[^12]: Probot Octokit access and webhook API. https://probot.github.io/docs/webhooks/ ; https://probot.github.io/docs/github-api/ (2026-06-30)
[^13]: n8n Community Edition. https://n8n.io/pricing/ (2026-06-30)
[^14]: n8n Cloud Starter plan pricing. https://n8n.io/pricing/ (2026-06-30)
[^15]: ECC Tools POC — live test. Repo: https://github.com/alfredo-compulabsperu/ecc-tools-poc, Issue #1, PR #2. (2026-06-30)
[^16]: ECC Tools pricing tiers. https://github.com/ECC-Tools/.github/blob/main/README.md (2026-06-30)

---

## Historial de versiones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-06-30 | Creación inicial — síntesis de 15 claims verificados (adversarial 3-vote), fetch de ecc.tools/pricing |
| 1.1 | 2026-06-30 | ECC Tools Finding 2 añadido — POC en vivo confirmó scope config-only; open question cerrado; trigger `opened` clarificado como fully autonomous |

## Generación

**Prompts usados:**
- `"Which tools for automating GitHub issue triage and autonomous issue work integrate natively with GitHub — compare and rank: GitHub Actions + claude -p, Probot, GitHub Apps, n8n, and webhooks + custom server"`
- `"Also fetch and incorporate pricing data from https://ecc.tools/pricing"`
- `"15 claims survived 3-vote adversarial verification. Merge semantic duplicates and synthesize."`

**Herramientas:**
- `WebFetch` (ecc.tools/pricing)
- Adversarial verification harness (3-vote, 15 confirmed claims across primary sources: anthropics/claude-code-action, probot/probot, npmjs.com, n8n.io/pricing, docs.github.com)
