# iOS SMS capture (Shortcuts → Supabase → app)

iOS has no SMS-read API, so the iPhone forwards bank SMS itself: a **Shortcuts
automation** fires on incoming messages and POSTs the text to a tiny Supabase
Edge Function. That function **parses the SMS as it arrives** and stores the
result in `detected_transactions`, which every signed-in device reads.

```
iPhone SMS → Shortcuts automation → ingest-sms Edge Function
          → parses immediately → detected_transactions → Detected card
             (on every device, no app-open needed)
```

Parsing used to wait for the app to be opened, which on iOS could be days —
nothing of ours can run in the background there, so detections appeared in a
late batch. Parsing server-side removes that gap. If the function can't parse
(no key, quota, model error) the raw row stays `status='new'` and the app's own
drain still handles it on next open, exactly as before.

Android keeps parsing on-device (its receiver is instant either way) and
publishes its detections to the same table, so a phone-detected SMS shows up on
the web app too, and adding or dismissing a card clears it everywhere.

Auth is a **per-user ingest token** generated in the app (Settings → Connect
iPhone SMS) — requires being signed in.

## 1. Create the tables (SQL Editor)

Safe to re-run: the tables use `if not exists`, and each policy is dropped
before it is recreated. (Without those drops a second run dies on
`42710: policy ... already exists`, and because the editor runs the whole
script as one transaction, *nothing* commits — including anything new further
down.)

```sql
create table if not exists public.ingest_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.ingest_tokens enable row level security;

drop policy if exists "Users manage their own ingest tokens"
  on public.ingest_tokens;

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

drop policy if exists "Users manage their own ingested sms"
  on public.ingested_sms;

create policy "Users manage their own ingested sms"
  on public.ingested_sms
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Parsed detections, shared by every device. Deliberately its own table
-- rather than part of the whole-account snapshot: a detection must survive
-- last-write-wins, and each device decides add/dismiss independently.
create table if not exists public.detected_transactions (
  id                text primary key,          -- stable per source SMS
  user_id           uuid not null references auth.users(id) on delete cascade,
  amount            numeric not null,
  occurred_at       timestamptz not null,
  raw_body          text not null,
  status            text not null default 'pending',  -- pending|added|dismissed
  linked_expense_id text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists detected_transactions_user_status_idx
  on public.detected_transactions (user_id, status, occurred_at desc);

alter table public.detected_transactions enable row level security;

drop policy if exists "Users manage their own detected transactions"
  on public.detected_transactions;

create policy "Users manage their own detected transactions"
  on public.detected_transactions
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
  paste the file → Deploy. **Redeploy after any change to this file** — the
  dashboard runs the copy you pasted, not the one in git.
- **CRITICAL: turn OFF "Verify JWT"** for this function (Shortcuts can't send
  one; the ingest token is the auth). Same lesson as the send-sms hook.
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected.
- For server-side parsing it reads the **same secrets as gemini-proxy**:
  `GEMINI_API_KEY` (+ optional `GEMINI_MODEL`, `GROQ_API_KEY`, `GROQ_MODEL`).
  Secrets are project-wide, so if gemini-proxy already works there is nothing
  to add. Without them the function still queues the SMS and the app parses it
  on next open, i.e. the old behaviour.

## 3. In the app

Settings → **Connect iPhone SMS** (visible when signed in) → it generates your
ingest token and shows the endpoint URL. Copy both for step 4.

## 4. On the iPhone (Shortcuts app)

1. **Automation** tab → **+** → **Message**.
2. Condition: **Message Contains** → the word your bank actually uses, `debited`
   or `sent` (UPI apps usually say "sent") → and select **Run Immediately**
   (verify this on your iOS version; test how it behaves while locked).
3. Add action: **Get Contents of URL**
   - URL: `https://<your-project-ref>.supabase.co/functions/v1/ingest-sms`
   - Method: **POST**, Request Body: **JSON**
     - `token` → *(paste your ingest token)*
     - `body` → the **Shortcut Input / Message** magic variable
4. Optional: add a **Show Notification** action after the URL one if you want
   the iPhone to announce the capture. (Android posts its own notification with
   Add/Ignore buttons; iOS can only announce — you still open Lekha to decide.)
5. Done. One automation matches one word, so repeat it for every wording your
   banks use (`sent`, `debited`, `spent`, `withdrawn`) — the parser treats them
   all as debits and filters false positives.

## Notes

- Start with **one bank keyword** and confirm end-to-end before adding more.
- Rows stay `new` until the app successfully parses them (offline-safe retry);
  parsed rows are marked `done`.
- The Android app drains the same queue, so iPhone-captured SMS show up
  everywhere you're signed in.
- Privacy: the SMS body transits your Supabase project and the Gemini API —
  the same trust model as the Android auto-detect.
