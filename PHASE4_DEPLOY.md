# Sound Board — Phase 4 Deploy Guide (Vercel + Supabase Auth)

## Why there's a build step at all

Sound Board is a single static HTML file — no Vite, no webpack, no framework.
A plain static file can't read `import.meta.env` or `process.env` in the
browser, so environment variables can't be "used" directly by `index.html`
the way they can in a real Vite app. `build.js` is a small script that
substitutes them into the HTML **at deploy time**, before Vercel serves it.
This is the standard pattern for "env vars in a framework-less static site."

Files involved:
- `index.html` — contains the placeholder tokens `__VITE_SUPABASE_URL__`,
  `__VITE_SUPABASE_ANON_KEY__`, `__VITE_GOOGLE_MAPS_API_KEY__`
- `build.js` — replaces those tokens with real values from Vercel's env vars
- `vercel.json` — tells Vercel to run `node build.js` and serve the `public/`
  folder it produces

## 1. Set up Supabase (if you haven't already)

Run, in order, in the Supabase SQL Editor:
1. `schema.sql`
2. `phase2_analytics_and_management.sql`
3. `phase3_storage.sql`
4. `phase4_roles_and_auth.sql`

Then: **Authentication → Providers → Google** → paste your Google OAuth
Client ID + Client Secret, toggle it on.

## 2. Set up Google OAuth redirect URLs

Two places need your real domain once you have one:

**Google Cloud Console** (APIs & Services → Credentials → your OAuth Client):
- Authorized redirect URIs: add
  `https://<your-supabase-project-ref>.supabase.co/auth/v1/callback`
  (Supabase shows you this exact URL on its Google provider settings page)

**Supabase** (Authentication → URL Configuration):
- Site URL: `https://your-app.vercel.app` (or your custom domain)
- Redirect URLs: add `https://your-app.vercel.app/**`

Without both of these, Google will redirect back to an error page instead
of your app after sign-in.

## 3. Add the environment variables in Vercel

Project → Settings → Environment Variables → add all three, for
Production (and Preview, if you want previews to hit the real backend too):

| Name | Value |
|---|---|
| `VITE_SUPABASE_URL` | Your Supabase project URL, e.g. `https://xxxxxxxx.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | Your Supabase **anon/public** key (Settings → API) |
| `VITE_GOOGLE_MAPS_API_KEY` | Your Google Maps JavaScript API key |

**Important — what's safe to expose and what isn't:**
- The Supabase **anon key** is *meant* to be public — it's what every
  Supabase JS app ships to the browser. Real protection comes from Row
  Level Security (which this project has, on every table), not from
  hiding this key.
- **Never** put your Supabase **service_role key** here, or anywhere in
  this repo. That key bypasses RLS entirely — it's server-only, and this
  app has no server component that would ever need it.
- The Google Maps API key should be **restricted** in Google Cloud Console
  (HTTP referrer restriction → your Vercel domain) so it can't be reused
  from other sites even though it's visible in your page source. This is
  normal for Maps JavaScript API keys — they're designed to be
  domain-restricted rather than hidden.

## 4. Deploy

Push to your connected Git repo, or run `vercel --prod`. Vercel will:
1. Run `node build.js` (per `vercel.json`)
2. `build.js` reads your env vars, substitutes them into `index.html`,
   writes the result to `public/index.html`
3. Vercel serves `public/` as the site

If any of the three env vars are missing, `build.js` logs a warning during
the build but **does not fail the deploy** — the app just runs in
demo/local mode (exactly like it does today) until you add them.

## 5. First real test, once deployed

1. Open your Vercel URL, click "Continue with Google" — this now does a
   real redirect to Google and back (not the old popup/JWT flow).
2. Confirm you land back in the app signed in, and that refreshing the
   page keeps you signed in (that's `getSession()` restoring the session).
3. Check your Supabase Table Editor → `profiles` — your row should exist,
   with `role = 'founder'` if you signed in with `khannaadhrit@gmail.com`,
   otherwise `role = 'user'`.
4. Click Log Out, confirm you land back on the Welcome screen and a
   refresh doesn't silently sign you back in.
5. If you're the founder: Settings → Founder Dashboard should now appear —
   check the User Management section shows your own account.

## 6. Promoting your first studio owner

There's no self-serve "become a studio owner" flow yet (that's a
reasonable next feature) — for now, promote someone via the Founder
Dashboard's User Management section (search their email → "Make Studio
Owner"), then manually set `owner_id` on their studio's row in the
`studios` table via the Supabase Table Editor.
