#!/usr/bin/env node
// SessionStart hook: warn if context-mode plugin is not installed or not enabled.

import { existsSync, readFileSync } from 'node:fs';
import { join, resolve, sep } from 'node:path';
import { homedir } from 'node:os';

const home = homedir();
const settingsPath = join(home, '.claude', 'settings.json');
const installedPath = join(home, '.claude', 'plugins', 'installed_plugins.json');

const issues = [];

// Check enabled in settings
try {
  const settings = JSON.parse(readFileSync(settingsPath, 'utf8'));
  if (settings?.enabledPlugins?.['context-mode@context-mode'] !== true) {
    issues.push('not enabled in settings.json (enabledPlugins)');
  }
} catch {
  issues.push('could not read ~/.claude/settings.json');
}

// Check install path is present and exists on disk
try {
  const installed = JSON.parse(readFileSync(installedPath, 'utf8'));
  const entries = installed?.plugins?.['context-mode@context-mode'] ?? [];
  const cacheRoot = resolve(home, '.claude', 'plugins', 'cache');
  const valid = entries.some(e => {
    if (!e.installPath) return false;
    if (!resolve(e.installPath).startsWith(cacheRoot + sep)) return false;
    return existsSync(e.installPath);
  });
  if (!valid) {
    issues.push('install path missing or broken — run /context-mode:ctx-doctor');
  }
} catch {
  issues.push('installed_plugins.json unreadable or missing context-mode entry');
}

if (issues.length > 0) {
  console.log(
    '[WARN] context-mode may not be active: ' + issues.join('; ') + '. ' +
    'Run /context-mode:ctx-doctor to diagnose.'
  );
}

process.exit(0);
