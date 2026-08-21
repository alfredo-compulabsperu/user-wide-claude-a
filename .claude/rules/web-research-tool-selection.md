# Web Research Tool Selection

To find sources/URLs on a topic — semantic or concept-based search, not extraction — Claude SHOULD use Exa (`ecc:exa-search` inside `research-ops`/`deep-research`; `exa:search` or `exa:agent` standalone) before `WebSearch`.

Once target URL(s) are known — one page, a whole site, or paginated listings — Claude SHOULD use Firecrawl rather than fetching manually: `firecrawl:firecrawl-scrape` for one page, `firecrawl:firecrawl-crawl` for a site section, `firecrawl:firecrawl-map` for URL discovery on a known site, `firecrawl:firecrawl-monitor` for recurring change-tracking.

Claude SHOULD reach for a real browser — Playwright, or the Chrome DevTools MCP (`mcp__plugin_ecc_chrome-devtools__*`) tools where available — only when the target needs login, clicks, form-fills, or JS the tools above can't render. Try `firecrawl:firecrawl-interact` first; escalate to a full browser session only if that's insufficient.

These three are pipeline stages, not competing choices: Exa finds candidate URLs, Firecrawl bulk-extracts their content, Playwright/chrome-devtools handles the subset needing auth or interaction.

A repo's own CLAUDE.md or `.claude/rules/*.md` MAY specify a different tool or flow for web research — e.g. a project-specific scraping pipeline — and that repo-level rule takes precedence over this global default.

Complements `research-ops-tool-compliance.md`, which forbids defaulting to `WebSearch` inside an active research skill, by specifying which of the skill's named tools fits the scenario.

Full sourced comparison: KB repo `projects/research-tool-selection-exa-firecrawl-playwright.md`, mirrored in this project's Claude Code memory.
