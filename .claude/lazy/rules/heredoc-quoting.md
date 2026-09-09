---
on:
  tools: [Bash]
  commands: ["*<<'*", "*<<\"*", "gh issue create*", "gh issue edit*", "gh pr create*", "gh pr comment*", "gh pr edit*", "git commit*"]
---
# Heredoc Quoting

## Required

When writing a shell heredoc body via a single-quoted delimiter (`<<'EOF' ... EOF`), Claude MUST NOT escape backticks, `$`, or `\` inside the block — the quoting already disables all shell interpretation (command substitution, variable expansion), so content between the markers passes through byte-for-byte. Escaping backticks defensively (`` \` `` instead of `` ` ``) inside a single-quoted heredoc writes the literal backslash into the output — e.g. a GitHub issue/PR body renders `` \`.env\` `` instead of `` `.env` `` in Markdown, breaking inline-code formatting. This applies to `gh issue create`/`gh issue edit`/`gh pr create`/`gh pr comment` `--body "$(cat <<'EOF' ... EOF)"` bodies, `git commit -m "$(cat <<'EOF' ... EOF)"` messages, and any other command body built from a single-quoted heredoc.

An unquoted heredoc (`<<EOF ... EOF`, or a double-quoted string) is different — it DOES expand `` `...` ``, `$(...)`, and `$VAR`, so escaping those characters is correct there. Before escaping anything, Claude MUST check whether the delimiter is quoted (`'EOF'`) or bare (`EOF`) and only escape for the latter. After creating or editing a `gh` issue/PR/comment body from a heredoc, Claude MUST re-fetch or view the created content and confirm it shows plain backticks, not `` \` ``.
