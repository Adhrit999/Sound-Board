# Sound Board — Backend & Deployment Guide (Phase 3)

This covers: setting up Supabase, running the SQL migration, configuring
Google sign-in through Supabase, and deploying to Vercel without exposing
any secrets in the repo.

## What changed vs. the old build

- No more hardcoded `SUPABASE_CONFIG.url` / `anonKey` / `FOUNDER_EMAILS` /
  `MAPS_CONFIG.apiKey` in `index.html`. Those now come from
  `window.__ENV__`, which is generated **at build time** from Vercel
  environment variables by `build.js`.
- Founder access is now a real `role` column in the `profiles` table,
  enforced by Postgres Row Level Security — not a front-end whitelist.
- Sign-in, sessions, profiles, studio ownership, and bookings are backed
  by real Supabase tables when the three env vars below are set. With no
  env vars set, the app runs exactly as it did before (local/demo mode).

---

## 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → New Project.
2. Once it's up, go to **Project Settings → API** and copy:
   - **Project URL** → this is `VITE_SUPABASE_URL`
   - **anon public key** → this is `VITE_SUPABASE_ANON_KEY`

   (The anon key is safe to ship to the browser — it has no power on its
   own; every table is locked down with the RLS policies in the migration.)

## 2. Run the SQL migration

1. In Supabase, open **SQL Editor → New Query**.
2. Paste the entire contents of `supabase_migration.sql` and run it.
3. This creates: `profiles`, `studios`, `bookings`, `page_views`,
   `studio_blocked_slots`, `studio_photos`, the `studio-photos` storage
   bucket, every RLS policy, the `handle_new_user` trigger (auto-creates a
   profile on sign-up and auto-assigns the `founder` role to
   `khannaadhrit@gmail.com`), and the RPC functions the dashboards call.
4. It also seeds the six demo studio listings (`basement9`, `cuepoint`,
   etc.) with `owner_id = NULL`. Once a real studio owner has signed in at
   least once (so they have a `profiles` row), assign them with:
   ```sql
   update public.studios set owner_id = '<their-profiles-id>' where id = 'basement9';
   ```

## 3. Enable Google sign-in

1. In Supabase: **Authentication → Providers → Google** → toggle it on.
2. You need a Google OAuth Client ID/Secret from
   [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
   (OAuth consent screen + "Web application" credentials).
3. In the Google Cloud credential's **Authorized JavaScript origins**, add
   your Vercel domain (e.g. `https://your-app.vercel.app`) and
   `http://localhost:3000` for local testing.
4. Paste the Google **Client ID** into Supabase's Google provider settings
   AND into `index.html`'s existing `data-client_id="..."` attribute (the
   `g_id_onload` div near the top of the auth screen markup) — this one
   value isn't secret and isn't part of the three env vars above, since
   it's meant to be publicly embedded (same as before).
5. The app already sends Google's ID token straight to
   `supabase.auth.signInWithIdToken()` when the backend is enabled — no
   redirect flow, no extra code needed.

## 4. Set environment variables on Vercel

In your Vercel project: **Settings → Environment Variables**, add:

| Name                        | Value                                  |
|------------------------------|-----------------------------------------|
| `VITE_SUPABASE_URL`          | your Supabase Project URL               |
| `VITE_SUPABASE_ANON_KEY`     | your Supabase anon public key           |
| `VITE_GOOGLE_MAPS_API_KEY`   | your Google Maps JavaScript API key     |

Apply them to whichever environments you need (Production / Preview /
Development). **Never** put the Supabase `service_role` key here — it's
never used by this app and should never reach the browser.

## 5. Deploy

`vercel.json` is already set up so Vercel just needs:

- **Build Command:** `node build.js` (already in `vercel.json`)
- **Output Directory:** `dist` (already in `vercel.json`)

Push the repo (containing `index.html`, `build.js`, `vercel.json`,
`supabase_migration.sql`) to your Git provider and import it in Vercel, or
run `vercel --prod` from the CLI. On every build, `build.js` reads the
three `VITE_*` variables from Vercel's environment and writes a fresh
`dist/env-config.js` — the actual secret values are never committed to
git, never appear in `index.html`'s source, and only exist inside the
build output that Vercel serves.

### Verifying it worked

After deploying, open your site and check DevTools → Network for
`env-config.js` — it should return a small script setting
`window.__ENV__` to your real values (not the `YOUR_..._KEY` placeholders).
If Supabase is wired correctly:

- The Google sign-in button creates a real Supabase session (visible under
  **Authentication → Users** in Supabase).
- Refreshing the page keeps you signed in (`supabase.auth.getSession()`
  restore).
- Signing in as `khannaadhrit@gmail.com` shows the Founder Dashboard, with
  a working User Management search/role-change list.
- Any other account does **not** see the Founder Dashboard entry, and
  attempting to call the founder-only RPCs/table updates directly (e.g.
  from DevTools) fails — RLS rejects it server-side regardless of what the
  client sends.

### Running locally without secrets

Just open `index.html` directly, or serve the folder with any static
server. With no `env-config.js` present, `window.__ENV__` stays undefined,
`BACKEND_ENABLED` is `false`, and the app runs in the original local/demo
mode — nothing crashes.
