# Auth setup (Supabase + Google)

Sign-in is **optional** — the app works fully offline. Signing in turns on
cloud backup & cross-device sync, and carries existing offline data into the
account on first login.

## App identifiers

| Thing | Value |
|---|---|
| Package name | `com.expanse.personal_tracker` |
| Debug SHA-1 (also signs release builds) | `<your-debug-sha1>` |
| OAuth redirect (deep link) | `com.expanse.personaltracker://login-callback` |
| Supabase project ref | `<your-project-ref>` |
| Supabase OAuth callback | `https://<your-project-ref>.supabase.co/auth/v1/callback` |

`SUPABASE_URL` / `SUPABASE_ANON_KEY` live in `.env` (not committed).

---

## Track 1 — Email / password (works out of the box)

Supabase project is already configured in `.env`. Optional:

- Supabase → **Authentication → Providers → Email** → turn **off "Confirm
  email"** for instant signup (otherwise users confirm via an emailed link
  before their first login).

---

## Track 2 — Google sign-in

Uses Supabase's **browser-based OAuth** (`signInWithOAuth`). Only a **Web**
OAuth client is required — no native Android client, no `google_sign_in`
package, no SHA-1 in code.

### A. Google Cloud — consent screen
1. https://console.cloud.google.com → create/select a project.
2. **APIs & Services → OAuth consent screen** → External → app name + your
   email → Save.
3. Add your Google account under **Test users** (needed while unpublished).

### B. Google Cloud — Web client
4. **Credentials → Create credentials → OAuth client ID → Web application**.
5. **Authorized redirect URIs** → add the Supabase OAuth callback:
   `https://<your-project-ref>.supabase.co/auth/v1/callback`
6. Create → copy the **Client ID** and **Client secret**.

> The **Android** client type is NOT needed for this flow — skip it.

### C. Supabase — enable Google
7. Supabase → **Authentication → Providers → Google** → enable.
8. Paste the Web **Client ID** + **Client secret** → Save.
   Leave "Skip nonce checks" and "Allow users without an email" off.

### D. Supabase — allow the app redirect (critical)
9. **Authentication → URL Configuration → Redirect URLs → Add URL**:
   `com.expanse.personaltracker://login-callback` → Save.
   Without this the app can't receive the callback and login fails silently.

### E. Test
10. Rebuild + install the APK → **Continue with Google** → pick account →
    returns to the app signed in.

---

## Track 4 — Cloud sync (run this SQL once)

Sync stores the whole account as one JSON snapshot per user (same data as
Export/Import: expenses, debts, budgets, salary cycles + history, categories,
pending SMS, settings). Create the table + row-level security so each user can
only touch their own snapshot.

Supabase → **SQL Editor** → run:

```sql
create table if not exists public.user_backups (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  snapshot   jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.user_backups enable row level security;

create policy "Users manage their own backup"
  on public.user_backups
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

How it flows:
- **Sign in** → local offline data is carried into the account, then pushed up.
- **App backgrounded / manual sync** → pushes the latest snapshot.
- **Another device signs in** (or a device with older data opens) → pulls the
  newer snapshot and restores everything.

ponytail ceiling: whole-snapshot last-write-wins. Great for one person across a
couple of devices used one at a time; simultaneous offline edits on two devices
mean the later sync wins and the other's unsynced edits are dropped.

## Track 5 — AI proxy (run once; keeps the Gemini key off clients)

All AI features call the `gemini-proxy` Edge Function instead of Google
directly, so the Gemini key lives server-side and never ships in the web
bundle or APK. Only signed-in users can call it (JWT-verified).

1. Supabase → **Edge Functions → Create a function** → name `gemini-proxy` →
   paste `supabase/functions/gemini-proxy/index.ts` → Deploy.
2. **Leave "Verify JWT" ON** (the default) — that's the auth gate.
3. **Edge Functions → Secrets** → add:
   - `GEMINI_API_KEY` = your Google AI Studio key
   - `GEMINI_MODEL` = optional (defaults to gemini-3.1-flash-lite)
4. Remove `GEMINI_API_KEY` from the GitHub Actions secrets and from local
   `.env` — the app no longer reads them.

## Phone OTP — removed

Phone login was tried and removed; the app ships **email + Google only**. If you
ever want it back, it's `signInWithOtp`/`verifyOTP` on the app side plus a
Supabase "Send SMS" hook to a gateway (Twilio / MSG91 / 2Factor). Clean up any
leftover Supabase config: disable **Auth → Providers → Phone** and the
**Auth → Hooks → Send SMS** hook.

---

## How it hangs together (code)

- `lib/services/auth/auth_service.dart` — email/password + `signInWithGoogle()`
  (Supabase OAuth), exposes `onAuthChange` stream.
- `lib/providers/auth/auth_provider.dart` — mirrors the Supabase auth stream,
  runs `reassignUserData` (local → account) on first sign-in.
- `lib/screens/auth/login_screen.dart` — the optional login/signup UI.
- `lib/main.dart` — one-time prompt after onboarding (skippable).
- `android/app/src/main/AndroidManifest.xml` — deep-link intent filter for the
  OAuth redirect.
