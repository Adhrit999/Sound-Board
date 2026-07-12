// build.js
// ----------------------------------------------------------------------------
// Sound Board has no bundler (no Vite/webpack) — it's one static HTML file.
// A plain static file can't read `import.meta.env` or `process.env` in the
// browser, so environment variables need to be substituted into the HTML
// at DEPLOY time instead. This script does exactly that: it's what Vercel
// runs during the build step (see vercel.json), replacing the placeholder
// tokens in index.html with the real values from your Vercel Environment
// Variables, then writing the result to /public for Vercel to serve.
//
// This is the standard, safe pattern for "env vars in a static site with no
// framework" — nothing here is Vite-specific despite the VITE_ prefix on
// the variable names (that prefix is just the naming convention this
// project uses; this script is what actually does the substitution).
// ----------------------------------------------------------------------------
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'index.html');
const OUT_DIR = path.join(__dirname, 'public');
const OUT = path.join(OUT_DIR, 'index.html');

const REQUIRED_VARS = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY', 'VITE_GOOGLE_MAPS_API_KEY'];

let html = fs.readFileSync(SRC, 'utf8');

let missing = [];
for (const key of REQUIRED_VARS) {
  const value = process.env[key];
  if (!value) {
    missing.push(key);
    continue; // leave the placeholder in place; BACKEND_ENABLED will just stay false
  }
  const token = '__' + key + '__';
  html = html.split(token).join(value);
}

if (missing.length) {
  console.warn(
    '[build.js] Missing environment variables: ' + missing.join(', ') +
    ' — the app will still build and deploy, but will run in demo/local mode ' +
    '(no real Supabase/Maps) until these are set in Vercel → Settings → Environment Variables.'
  );
} else {
  console.log('[build.js] All environment variables injected successfully.');
}

fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT, html);
console.log('[build.js] Wrote ' + OUT);
