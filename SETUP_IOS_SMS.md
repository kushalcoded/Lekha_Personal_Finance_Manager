# iOS SMS capture (Shortcuts → Supabase → app)

iOS has no SMS-read API, so the iPhone forwards bank SMS itself: a **Shortcuts
automation** fires on incoming messages and POSTs the text to a tiny Supabase
Edge Function, which queues it per-user. The app (web or Android) drains that
queue through the **same Gemini parse + dedup pipeline** as native Android SMS —
detected debits appear as the usual "Detected" cards.

```
iPhone SMS → Shortcuts automation → ingest-sms Edge Function → ingested_sms table
          → app drains on open/poll → Gemini parse → Detected card
```

Auth is a **per-user ingest token** generated in the app (Settings → Connect
iPhone SMS) — requires being signed in.

## 1. Create the tables (SQL Editor, run once)

```sql
create table if not exists public.ingest_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.ingest_tokens enable row level security;

create policy "Users manage their own ingest tokens"
  on public.ingest_tokens
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.ingested_sms (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  body        text not null,
  received_at timestamptz not null default now(),
  status      text not null default 'new',
  created_at  timestamptz not null default now()
);

alter table public.ingested_sms enable row level security;

create policy "Users manage their own ingested sms"
  on public.ingested_sms
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

(The Edge Function inserts with the service-role key, which bypasses RLS; the
app reads/updates only its own rows. Processed rows older than 30 days are
deleted automatically each time the app drains the queue — the recent window
stays so the connection health card can show when the last SMS arrived.)

## 2. Deploy the Edge Function

Code: `supabase/functions/ingest-sms/index.ts`.

- Dashboard → **Edge Functions → Create a function** → name `ingest-sms` →
  paste the file → Deploy.
- **CRITICAL: turn OFF "Verify JWT"** for this function (Shortcuts can't send
  one; the ingest token is the auth). Same lesson as the send-sms hook.
- No extra secrets needed — `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are
  auto-injected.

## 3. In the app

Settings → **Connect iPhone SMS** (visible when signed in) → it generates your
ingest token and shows the endpoint URL. Copy both for step 4.

## 4. On the iPhone (Shortcuts app)

1. **Automation** tab → **+** → **Message**.
2. Condition: **Message Contains** → `debited` → and select **Run Immediately**
   (verify this on your iOS version; test how it behaves while locked).
3. Add action: **Get Contents of URL**
   - URL: `https://<your-project-ref>.supabase.co/functions/v1/ingest-sms`
   - Method: **POST**, Request Body: **JSON**
     - `token` → *(paste your ingest token)*
     - `body` → the **Shortcut Input / Message** magic variable
4. Done. Repeat the automation for other keywords your banks use
   (`spent`, `withdrawn`, `Rs.`) — the app's parser filters false positives.

## Notes

- Start with **one bank keyword** and confirm end-to-end before adding more.
- Rows stay `new` until the app successfully parses them (offline-safe retry);
  parsed rows are marked `done`.
- The Android app drains the same queue, so iPhone-captured SMS show up
  everywhere you're signed in.
- Privacy: the SMS body transits your Supabase project and the Gemini API —
  the same trust model as the Android auto-detect.
