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

### 2. Schema — **written** (`8b8b9a6`), needs running

- [x] `SETUP_SHARE.md`: `shared_spaces`, `shared_people`, `shared_participants`,
      `shared_entries`, owner-scoped RLS, `revoke select (pin_hash, pin_salt)`.
      The owner's net sits on the participant row, not the space, so a group
      needs no new column.
- [ ] **Yours:** run it in the Supabase SQL editor. Re-runnable by design — run
      it twice to prove the `drop policy if exists` discipline holds.

### 3. Edge function — **written** (`8b8b9a6`), needs deploying

- [x] `supabase/functions/share/index.ts`, one function, actions `open` /
      `claim` / `login` / `add` / `forgot`. PBKDF2 + a server-side pepper,
      lockout after 5 wrong PINs that doubles, a stateless 7-day session revoked
      by bumping `pin_version`. Type-checks clean under `--strict`.
- [ ] **Yours:** paste it into the dashboard with **Verify JWT off**, and set
      `GUEST_PIN_PEPPER` and `GUEST_SESSION_SECRET` as function secrets.

### 4. The guest page — **done** (`e01b98b`), ships on the next push

- [x] `web/s/index.html`, one file, no framework, no build step. **23 KB raw,
      7 KB gzipped.**
- [x] Token in the fragment, cleared from the address bar on first read —
      verified in a browser.
- [x] System font stack, not Inter (876 KB). Money uses the same
      two-decimals-only-if-needed rule as `AppFormatters.formatCurrency`.
- [x] Reads the project URL from `/assets/.env` rather than keeping a second
      copy — verified resolving against the real project.
- [x] Verified in a browser at 375px: no sideways scroll, 46px minimum tap
      target, claim / login / ledger / add / settle / forgot / error all render,
      exact-split validation catches shares that don't add up.

### 5. Owner side in the app — **done** (`7abe7c6`)

- [x] A link action on the person ledger. **Changed from the plan:** its own
      action rather than appended to the AI reminder — a link at the end of a
      nudge about money reads like part of the nudge, and this is an invitation.
- [x] Pending cards on the person ledger, styled like the detected-SMS cards,
      each saying in words what accepting would do ("you would owe Rahul ₹600").
      PIN-reset requests appear beside them; allowing one bumps `pin_version`
      and signs out any week-old session.
- [x] Accept goes through `computeSplit` + `createSplitDebts` — the same pair
      the add-expense form uses, so there is no second way for money to enter
      the app. `test/shared_entry_accept_test.dart` covers both directions and
      the cases where one person covered the whole bill.
- [x] A sibling 60s poll, plus an immediate refresh when the Debts tab opens.

### 6. Simplify debts — **done** (`52f76a1`), wired to nothing on purpose

- [x] `simplify_debts.dart` + test. Called from nowhere until groups exist:
      with two people it can only ever return the number already on screen, and
      a Simplify button that never changes anything is worse than no button.

### 7. Groups — not started, and the only thing left

UI only. The schema already carries N participants per space, identity is
already per-person rather than per-space, and the reduction is already written
and tested. What is missing is a group screen, a second participant on a space,
and per-participant nets pushed for each member.

---

## What needs you, and when

| Step | You do | Why it can't be automated |
|---|---|---|
| 2 | Run the SQL | Dashboard access |
| 3 | Paste the function, set two secrets | Not deployed from git; secrets are yours |
| 5 | Open a share link on your phone once | Desktop web has no share sheet |
| — | Push to `main` | The guest page only exists once Pages redeploys |
| — | A real trial with a friend | Whether a stranger understands the page |

Everything else is verifiable here: a private browser window is a genuinely
fresh guest.
