# CLAUDE.md Self-Reference

## Required

A `CLAUDE.md` file (root or nested) MUST NOT list, cite, or point to its own path from within its own content — e.g. a table row like `` `docs/CLAUDE.md` (this file) `` inside `docs/CLAUDE.md` itself. Self-references go stale silently on rename or move — exactly what happened when `docs/system/CLAUDE.md` moved to `docs/CLAUDE.md` and its own self-referential table row needed a manual fix. A file describing its own role in prose doesn't need to name its own path.

This does NOT restrict one `CLAUDE.md` referencing a *different* `CLAUDE.md` — e.g. root `CLAUDE.md`'s `@docs/CLAUDE.md` import line is a normal, required cross-reference, not a self-reference.

## Advisory

A separate registry/index file (e.g. `docs/system/index.md`) MAY list a `CLAUDE.md` file's path as one of its entries — that's the registry doing its job on another file, not the `CLAUDE.md` file referencing itself.
