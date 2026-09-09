# Archiving

## Required
- When archiving a file, it MUST move to `archived/<original relative path>` (e.g. `docs/a.md` → `archived/docs/a.md`), preserving the full original path.
- Applies whenever archiving is requested without an explicit destination path — an explicit path given by the user overrides this default.
