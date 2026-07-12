// build.js — runs on Vercel as the project's Build Command.
//
// This is a static single-file app (index.html), so there's no bundler
// step required. All this script does is:
//   1. Read the three env vars Vercel injects at build time.
//   2. Write them into dist/env-config.js as window.__ENV__.
//   3. Copy index.html (and any other static files) into dist/.
//
// index.html itself never contains a real URL or key — it only reads
// window.__ENV__ at runtime (see the BACKEND (Supabase) — config & client
// section near the top of its <script>). So nothing secret ever needs to
// be committed to the repo.
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, 'dist');
fs.mkdirSync(OUT_DIR, { recursive: true });

// ---- 1 & 2: generate env-config.js ----
const env = {
  SUPABASE_URL: process.env.VITE_SUPABASE_URL || '',
  SUPABASE_ANON_KEY: process.env.VITE_SUPABASE_ANON_KEY || '',
  GOOGLE_MAPS_API_KEY: process.env.VITE_GOOGLE_MAPS_API_KEY || '',
};

for (const [key, value] of Object.entries(env)) {
  if (!value) {
    console.warn(`[build.js] Warning: VITE_${key} is not set — the app will run in demo mode for this feature.`);
  }
}

const envConfigContents = `// AUTO-GENERATED at build time by build.js — do not edit or commit.
window.__ENV__ = ${JSON.stringify(env, null, 2)};
`;
fs.writeFileSync(path.join(OUT_DIR, 'env-config.js'), envConfigContents);

// ---- 3: copy index.html into dist/ ----
fs.copyFileSync(path.join(__dirname, 'index.html'), path.join(OUT_DIR, 'index.html'));

console.log('[build.js] Wrote dist/index.html and dist/env-config.js');
