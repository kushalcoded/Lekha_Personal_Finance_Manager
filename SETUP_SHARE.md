# Shared pages (link → guest page → pending in your app)

You share a link with someone who does **not** use Lekha. They open a small web
page at `lekhamoney.app/s/`, see the ledger the two of you share, and can add an
expense or record a settlement. Everything they do arrives in your app as a card
you accept or dismiss — the same shape as a detected SMS.

```
you → share link → /s/#<token> → guest names a 4-digit PIN
                              → adds an expense
   → shared_entries (pending) → card in your app → accept
                              → real expense + debt, via the normal write path
```

**Whoever creates a link controls it.** There is no admin account: every row
carries `owner_id`, and a forgotten PIN goes to the person who made the link.

**A guest's identity is `(owner_id, name_key)`** — one PIN per person per owner,
shared across their one-to-one page and every group. Two Lekha users sharing
with their own Rahul are two separate identities.

**The PIN is four digits on purpose.** No money moves through this page; it
records who owes whom and transfers nothing. The claim screen says the session
lasts a week and the PIN will be asked for again, so people pick one they will
remember. The real defences are that the link is needed before a PIN is even
asked for, that guessing is rate-limited, and that the hash is peppered with a
secret that lives in the function rather than the database.

**Guests get no RLS policies at all.** Their browser never talks to PostgREST —
only to the `share` Edge Function, which holds the service-role key and
bypasses RLS. Nothing here is granted to `anon`: the anon key ships inside the
app bundle and is public, so an `anon` grant is a grant to the internet.

## 1. Create the tables (SQL Editor)

Safe to re-run: the tables use `if not exists`, and each policy is dropped
before it is recreated. (Without those drops a second run dies on
`42710: policy ... already exists`, and because the editor runs the whole
script as one transaction, *nothing* commits — including anything new further
down.)

```sql
-- One shared ledger. Pairwise today is a space with exactly one participant;
-- a group is the same space with several. Nothing here changes for groups.
create table if not exists public.shared_spaces (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  title       text,
  owner_name  text not null,
  created_at  timestamptz not null default now(),
  archived_at timestamptz
);

-- A guest's identity, global per owner. The PIN hangs here rather than on the
-- membership row, which is what makes one PIN work in the one-to-one page and
-- in every group at once.
create table if not exists public.shared_people (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users(id) on delete cascade,
  name         text not null,
  name_key     text not null,
  pin_hash     text,
  pin_salt     text,
  -- Bumping this invalidates every live session for the person; it is the only
  -- revocation the feature needs, and it is free.
  pin_version  int not null default 1,
  -- Shown to the owner. If a link is forwarded before the intended person
  -- opens it, whoever opens it first sets the PIN — this is what lets the
  -- owner notice ("Rahul set a PIN on the 21st"? he says he didn't) and reset.
  pin_set_at   timestamptz,
  failed_count int not null default 0,
  locked_until timestamptz,
  pin_reset_requested_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (owner_id, name_key)
);

-- Membership plus the share link itself.
create table if not exists public.shared_participants (
  token        text primary key,
  owner_id     uuid not null references auth.users(id) on delete cascade,
  space_id     uuid not null references public.shared_spaces(id) on delete cascade,
  person_id    uuid not null references public.shared_people(id) on delete cascade,
  -- The owner's net WITH THIS PERSON, positive when the owner is owed. Written
  -- by the app from its own balances and only echoed by the function: the
  -- server has no idea what was owed before the link existed, so any total it
  -- summed here would disagree with the app by construction. Per-participant
  -- rather than per-space so a group needs no new column.
  owner_net    numeric not null default 0,
  revoked_at   timestamptz,
  last_seen_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (space_id, person_id)
);

-- What a guest did, waiting on the owner. Deliberately the same vocabulary as
-- detected_transactions, because it is the same accept/dismiss card.
create table if not exists public.shared_entries (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references auth.users(id) on delete cascade,
  space_id          uuid not null references public.shared_spaces(id) on delete cascade,
  author_person_id  uuid references public.shared_people(id) on delete set null,
  kind              text not null default 'expense',
  total             numeric not null,
  payer_name        text not null,
  shares            jsonb not null default '{}'::jsonb,
  note              text,
  occurred_on       date not null default current_date,
  status            text not null default 'pending',
  linked_expense_id text,
  created_at        timestamptz not null default now(),
  decided_at        timestamptz
);

create index if not exists shared_entries_owner_status_idx
  on public.shared_entries (owner_id, status, created_at desc);
create index if not exists shared_participants_space_idx
  on public.shared_participants (space_id);
create index if not exists shared_spaces_owner_idx
  on public.shared_spaces (owner_id) where archived_at is null;

alter table public.shared_spaces       enable row level security;
alter table public.shared_people       enable row level security;
alter table public.shared_participants enable row level security;
alter table public.shared_entries      enable row level security;

-- owner_id is denormalised onto all four tables so every policy is the same
-- single comparison, and so a guest's traffic never needs a join to be scoped.
drop policy if exists "Owners manage their own spaces" on public.shared_spaces;
create policy "Owners manage their own spaces"
  on public.shared_spaces
  for all
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "Owners manage their own people" on public.shared_people;
create policy "Owners manage their own people"
  on public.shared_people
  for all
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "Owners manage their own participants"
  on public.shared_participants;
create policy "Owners manage their own participants"
  on public.shared_participants
  for all
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "Owners manage their own shared entries"
  on public.shared_entries;
create policy "Owners manage their own shared entries"
  on public.shared_entries
  for all
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- Nothing in the app ever needs to read a PIN hash. Column privileges compose
-- with RLS, so this costs one line and removes the hashes from every query the
-- app could possibly make.
revoke select (pin_hash, pin_salt) on public.shared_people from authenticated;
```

### Check it took

Run the script a second time. It should complete silently — if it errors, the
`drop policy` lines are wrong and nothing from the first run is trustworthy
either.

## 2. Deploy the Edge Function

Do section 1 first — the function talks to those four tables and will error on
every call until they exist.

### 2a. Make the two secrets

Generate them **before** opening the dashboard, so you can paste rather than
invent something memorable. Each wants 32 random bytes. In PowerShell:

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b)
```

Run it twice and keep both lines — one is `GUEST_PIN_PEPPER`, the other is
`GUEST_SESSION_SECRET`. (On a Mac or in git bash, `openssl rand -base64 32`
does the same job.)

| Secret | What it does | If you change it later |
|---|---|---|
| `GUEST_PIN_PEPPER` | Mixed into every PIN hash. It lives here and **not** in the database, which is what stops a database leak from exposing PINs — 10,000 combinations is otherwise trivially crackable. | **Every existing PIN stops working**, with no way to migrate them. Set it once. |
| `GUEST_SESSION_SECRET` | Signs the week-long session tokens. | Everyone is signed out and enters their PIN again. Harmless. |

Keep both somewhere you keep passwords. They are not in the repo and not
recoverable from it.

### 2b. Create the function

Supabase dashboard → **Edge Functions** → create a new function → name it
exactly **`share`** (the guest page builds its endpoint as
`<project-url>/functions/v1/share` — any other name and every call 404s).

Paste the whole of `supabase/functions/share/index.ts` in, replacing whatever
template it starts with, and deploy.

> Functions here are **not** deployed from git. Whatever is in the dashboard is
> what runs, so after editing the file locally you have to come back and paste
> it again. Same as `ingest-sms`.

### 2c. Turn Verify JWT OFF

In the function's settings, **disable "Verify JWT"**.

This is the step that is easy to miss and produces a confusing failure: with it
on, Supabase's gateway rejects every request *before* the function runs, so
you get a 401 that looks like your token is wrong when the code was never
reached. Guests have no Supabase account and no JWT — the share token in the
request body is the credential, exactly as `ingest-sms` works.

### 2d. Add the secrets

Edge Functions → **Secrets** → add `GUEST_PIN_PEPPER` and
`GUEST_SESSION_SECRET` with the two values from 2a.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically —
do not add those yourself.

### Check it took

You need a share token. Once the app ships you get one from **Debts → a person
→ the link icon**, but to test the function before then, make one by hand in
the SQL editor. Put your own sign-in email in the first line:

```sql
with me as (
  select id from auth.users where email = 'you@example.com'
), space as (
  insert into public.shared_spaces (owner_id, owner_name)
  select id, 'Kushal' from me
  returning id, owner_id
), person as (
  insert into public.shared_people (owner_id, name, name_key)
  select owner_id, 'Test Guest', 'test guest' from space
  returning id, owner_id
)
insert into public.shared_participants
  (token, owner_id, space_id, person_id, owner_net)
select md5(random()::text) || md5(random()::text),
       space.owner_id, space.id, person.id, 430
from space, person
returning token;
```

Copy the token it returns. Then, in git bash:

```bash
URL=https://YOUR-PROJECT.supabase.co/functions/v1/share
T=paste_the_token_here
call() { curl -s -X POST "$URL" -H 'content-type: application/json' -d "$1"; echo; }
```

Now run these in order. Each line tells you something different went right:

```bash
call '{"action":"open","t":"'$T'"}'
```

| Then run | Expect |
|---|---|
| the `open` above | `{"name":"Test Guest","ownerName":"Kushal","state":"claim"}` |
| `call '{"action":"claim","t":"'$T'","pin":"1234"}'` | an `s` (session token) and a `ledger` |
| the same `claim` again | `{"error":"already claimed"}` — a claimed identity can't be silently re-claimed |
| `call '{"action":"login","t":"'$T'","pin":"9999"}'` six times | `wrong pin` with a falling `left`, then `{"error":"locked","lockedFor":900}` |
| `call '{"action":"login","t":"'$T'","pin":"1234"}'` while locked | still `locked` — the right PIN does not bypass the wait |
| `call '{"action":"forgot","t":"total-nonsense"}'` | `{"ok":true}` — it must answer the same for a fake token, or it becomes a way to test guessed links |
| `curl -i -X OPTIONS "$URL"` | `200` and `access-control-allow-origin: *` — without this no browser can call it at all |

The lockout is the one worth actually running. It is the only thing standing
between a 4-digit PIN and someone with a script, and it cannot be unit-tested
from this repo.

To skip the 15-minute wait while testing:

```sql
update public.shared_people
set failed_count = 0, locked_until = null
where name_key = 'test guest';
```

And when you are done, remove the test rows:

```sql
delete from public.shared_spaces
where id = (select space_id from public.shared_participants
            where token = 'paste_the_token_here');
delete from public.shared_people where name_key = 'test guest';
```

### If something is wrong

| What you see | What it means |
|---|---|
| `{"error":"share secrets not configured"}`, 500 | 2d was skipped, or a name is misspelled |
| `401` with `Missing authorization header` | Verify JWT is still **on** (2c) |
| `{"error":"link not active"}`, 404 | Wrong token, or the participant row has `revoked_at` set |
| `relation "public.shared_people" does not exist` | Section 1 did not commit — re-run it and read the error at the top |
| Works in curl, fails in the browser | The `OPTIONS` check above; a missing CORS header shows up as "Failed to fetch" with no status |

## 3. The guest page

`web/s/index.html` ships with the normal web deploy — Flutter copies everything
under `web/` into `build/web/` untouched, so there is nothing extra to
configure and no routing change. Push to `main`, wait for Pages, then open
`https://lekhamoney.app/s/#<token>` **in a private window** — that is a
genuinely fresh guest, with its own storage.

GitHub Pages serves HTML with `Cache-Control: max-age=600`, so a change can take
ten minutes to appear. That is the only staleness here; the Flutter service
worker no longer caches anything and cannot intercept this page.

## Troubleshooting

**"This link isn't active any more."** The participant row has `revoked_at` set,
or the token is wrong. Share a fresh link from the person's ledger.

**A guest is locked out and cannot wait.** In the app, approve their reset — it
nulls the hash and bumps `pin_version`, which also signs out any device still
holding a session. Their next open asks them to pick a new PIN.

**Entries never reach the app.** The app polls once a minute and immediately
when you open that person's ledger. If they still don't arrive, check the app is
signed in — every query is scoped by `auth.uid()`, and a signed-out app reads
nothing rather than erroring.
