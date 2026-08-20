# Shared pages — build progress

A link you send to someone who does **not** use Lekha. They see the ledger you
share with them, add an expense, and settle up. Everything they do arrives in
your app as something you accept or dismiss — nothing writes to your books on
its own.

Full design: `~/.claude/plans/swift-bubbling-conway.md`.

---

## Ground rules this build follows

- **Anyone using Lekha can share a link, and whoever created it controls it.**
  There is no admin account. A forgotten PIN goes to the person who made the
  link, and only they can approve the reset.
- **One identity per person per creator.** The same Rahul, the same PIN, across
  his one-to-one page and every group you put him in. A different Lekha user
  sharing with their own Rahul is a separate identity; neither can touch the
  other's.
- **The PIN is four digits on purpose.** No money moves through the page — it
  records who owes whom, it does not transfer anything. The claim screen has to
  say plainly that the session lasts a week and the PIN will be asked for again,
  so people pick one they will remember.
- **Guests can never write to your ledger.** Their entries queue as pending and
  you accept them, the same way a detected SMS works.
- **Nothing is granted to `anon`.** The anon key ships inside the app bundle and
  is fully public. Guests reach data only through one Edge Function.

---

## Steps

### 1. Debts tab, made usable — **done** (`000e5f3`, `ce7dc95`)

- [x] One `showAddDebtSheet` replaces the chooser and both add modals. Amount
      first and autofocused, ranked people pills, direction as two pills, and a
      line spelling out who ends up owing whom.
- [x] **Bug fixed:** `+ Add a debt` sat inside the `else` of the empty check, so
      settling your last debt left no way to record another one — under an empty
      state telling you to "tap +", which is a different button entirely.
- [x] Long-press pin/hide extracted to `widgets/common/person_menu.dart` and
      shared with the split sheet instead of copied.
- [x] Deleted ~2,580 lines of unreachable payables/receivables UI.
- [x] `test/add_debt_direction_test.dart`, `mobile_add_debt` golden.
- [x] Pinned the `mobile_ledger` golden, which re-shot itself every day.

### 2. Schema — not started

- [ ] `SETUP_SHARE.md`: `shared_spaces`, `shared_people`, `shared_participants`,
      `shared_entries`, owner-scoped RLS, `revoke select (pin_hash, pin_salt)`.
- [ ] **Yours:** run it in the Supabase SQL editor. Re-runnable by design — run
      it twice to prove the `drop policy if exists` discipline holds.

### 3. Edge function — not started

- [ ] `supabase/functions/share/index.ts`, one function, actions `open` /
      `claim` / `login` / `add` / `forgot`. PBKDF2 + a server-side pepper,
      lockout after 5 wrong PINs, a stateless 7-day session revoked by bumping
      `pin_version`.
- [ ] **Yours:** paste it into the dashboard with **Verify JWT off**, and set
      `GUEST_PIN_PEPPER` and `GUEST_SESSION_SECRET` as function secrets.

### 4. The guest page — not started

- [ ] `web/s/index.html`, one file, no framework, no build step. Ships through
      the existing Pages workflow because `web/` is copied verbatim into
      `build/web/`.
- [ ] Token in the fragment (`/s/#<token>`) so it never reaches a server log,
      then cleared from the address bar on first read.
- [ ] System font stack, not Inter — the app's Inter is 876 KB and would blow
      the under-a-second budget on its own.

### 5. Owner side in the app — not started

- [ ] Share action on the person ledger; the link is appended to the reminder
      that already goes through the share sheet.
- [ ] Pending "from the shared page" cards on the person ledger, styled like the
      detected-SMS cards, plus PIN-reset requests.
- [ ] Accept reuses `createSplitDebts` and the existing expense write path — no
      new way for money to enter the ledger.
- [ ] A 60s poll alongside the existing SMS timer, not inside it.

### 6. Simplify debts — not started

- [ ] `simplify_debts.dart` + test. Written now, wired to no UI until groups
      exist: with two people it can only ever return the number already on
      screen.

### 7. Groups — not started

UI only. The schema already carries N participants per space.

---

## What needs you, and when

| Step | You do | Why it can't be automated |
|---|---|---|
| 2 | Run the SQL | Dashboard access |
| 3 | Paste the function, set two secrets | Not deployed from git; secrets are yours |
| 5 | Open a share link on your phone once | Desktop web has no share sheet |
| — | A real trial with a friend | Whether a stranger understands the page |

Everything else is verifiable here: a private browser window is a genuinely
fresh guest.
