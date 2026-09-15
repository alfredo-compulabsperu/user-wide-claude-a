# Plan: Bulk Opportunity Enrichment Pipeline

## Overview

Agent pipeline that enriches a batch of sales opportunities, has a career
coach agent synthesize a recommendation per opp, and writes results to a
shared review file for a human to approve.

## Stages

```
parallel([
  agent1: enrich-company-data(opp)   // fetches firmographic data per opp
  agent2: enrich-contact-data(opp)   // fetches contact/persona data per opp
  career-coach: synthesize(opp)      // reads agent1 + agent2 output, writes
                                      // a recommendation block to review.md
])
```

- Each opp gets a slug for tracking (derived from company name, no fixed
  format specified — whatever each agent generates).
- `career-coach` writes its recommendation directly into `review.md`,
  appending a section per opp.
- `agent1` and `agent2` also each append their raw findings to `review.md`
  for audit purposes.

## Verdict Extraction

Each agent returns a natural-language summary ending in something like
"Overall, I'd recommend: PURSUE" or "my verdict here is HOLD" — the
orchestrator reads the final agent output and moves the opp to the
appropriate pipeline stage based on that.

## Human-in-the-loop step

`career-coach`'s spec includes: "If you're unsure about an opp, pause and ask
the user whether to continue before writing your recommendation."

## Completion

Once all opps have a recommendation in `review.md`, the pipeline is done —
someone reviews `review.md` and acts on the recommendations manually.
