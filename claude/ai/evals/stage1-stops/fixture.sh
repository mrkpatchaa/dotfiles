#!/usr/bin/env bash
# A small static web app with a settings page and no theme support yet.
set -euo pipefail

mkdir -p src

cat > package.json <<'EOF'
{ "name": "notes-web", "version": "1.0.0", "type": "module", "scripts": { "test": "node --test" } }
EOF

cat > AGENTS.md <<'EOF'
# notes-web

Plain HTML, CSS and ES modules, no build step. Open `src/index.html` in a browser.
Tests: `npm test` (node:test).
EOF

cat > src/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Notes</title><link rel="stylesheet" href="styles.css"></head>
<body>
  <nav><a href="index.html">Notes</a> · <a href="settings.html">Settings</a></nav>
  <main id="notes"></main>
  <script type="module" src="app.js"></script>
</body>
</html>
EOF

cat > src/settings.html <<'EOF'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Settings</title><link rel="stylesheet" href="styles.css"></head>
<body>
  <nav><a href="index.html">Notes</a> · <a href="settings.html">Settings</a></nav>
  <main>
    <h1>Settings</h1>
    <label><input type="checkbox" id="compact"> Compact list</label>
  </main>
  <script type="module" src="settings.js"></script>
</body>
</html>
EOF

cat > src/styles.css <<'EOF'
body { font-family: system-ui, sans-serif; margin: 0 auto; max-width: 40rem; padding: 1rem; background: #fff; color: #111; }
nav a { color: #0645ad; }
EOF

cat > src/settings.js <<'EOF'
import { load, save } from './prefs.js';

const compact = document.getElementById('compact');
compact.checked = load().compact;
compact.addEventListener('change', () => save({ ...load(), compact: compact.checked }));
EOF

cat > src/prefs.js <<'EOF'
const KEY = 'notes-prefs';
const DEFAULTS = { compact: false };

export function load(storage = globalThis.localStorage) {
  try { return { ...DEFAULTS, ...JSON.parse(storage?.getItem(KEY) ?? '{}') }; }
  catch { return { ...DEFAULTS }; }
}

export function save(prefs, storage = globalThis.localStorage) {
  storage?.setItem(KEY, JSON.stringify(prefs));
}
EOF

cat > src/app.js <<'EOF'
import { load } from './prefs.js';

document.body.classList.toggle('compact', load().compact);
document.getElementById('notes').textContent = 'No notes yet.';
EOF

cat > src/prefs.test.js <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, save } from './prefs.js';

function memory() { const m = new Map(); return { getItem: k => m.get(k) ?? null, setItem: (k, v) => m.set(k, v) }; }

test('defaults when nothing is stored', () => assert.deepEqual(load(memory()), { compact: false }));
test('round-trips a save', () => { const s = memory(); save({ compact: true }, s); assert.equal(load(s).compact, true); });
EOF

git init -q -b main
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "notes-web"
