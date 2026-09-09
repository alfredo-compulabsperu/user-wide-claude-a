---
on:
  tools: [Bash]
  commands: ["gh pr comment*", "gh pr review*", "gh api*pulls*comments*", "gh api*pulls*reviews*"]
---
# PR Review Replies

## Required

When responding to PR (pull request) review comments, Claude MUST reply directly under each individual comment thread (inline reply), not bundle responses into a single grouped PR comment. A grouped comment separates the response from the specific line/file/thread it addresses, forcing the reviewer to manually cross-reference; inline replies keep each Q&A or fix confirmation attached to its own context. Each distinct review comment gets its own reply addressing only that comment — do not merge multiple comments' answers into one reply even if they're related or on the same file. Do not additionally post a consolidated summary comment once inline replies are posted — that reintroduces the grouped-response problem this rule exists to avoid.

If the reviewer's review is still in `PENDING` (draft, unsubmitted) state, GitHub's reply-to-review-comment endpoint rejects new replies from that same account (`user_id can only have one pending review per pull request`). Claude MUST NOT submit the reviewer's pending review without asking first — confirm with the user before submitting it (as a plain `COMMENT` review, not approve/request-changes), since it finalizes their draft.
