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

### 2. Schema — **done**, run on the live project

- [x] `SETUP_SHARE.md`: `shared_spaces`, `shared_people`, `shared_participants`,
      `shared_entries`, owner-scoped RLS, `revoke select (pin_hash, pin_salt)`.
      The owner's net sits on the participant row, not the space, so a group
      needs no new column.
- [x] Run in the Supabase SQL editor. Confirmed live: an unauthenticated call
      reaches the tables and is correctly refused.

### 3. Edge function — **done**, deployed with Verify JWT off

- [x] `supabase/functions/share/index.ts`, one function, actions `open` /
      `claim` / `login` / `add` / `forgot`. PBKDF2 + a server-side pepper,
      lockout after 5 wrong PINs that doubles, a stateless 7-day session revoked
      by bumping `pin_version`. Type-checks clean under `--strict`.
- [x] Deployed, both secrets set. Verified end to end against production:
      claim, add, settle, and the lockout — four warnings, then locked for 15
      minutes, and the **correct** PIN does not buy a way past the wait.

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

### 8. Fixes found by actually using it

- [x] **Reload looked like a dead link** (`604801d`). The token is wiped from
      the address bar for privacy, but nothing kept a copy, so a reload found an
      empty fragment and failed closed. Remembered now, and cleared on a 404 so
      a revoked link cannot leave the page permanently broken.
- [x] **The guest saw a balance with nothing behind it** (`f4e0424`). Only the
      net was being pushed. The app now projects its open items too, skipping
      anything the guest already submitted so shared bills do not appear twice,
      and removing rows for debts deleted locally.
- [x] **The reset card never appeared** (`f4e0424`) — a server-side
      `not.is.null` filter that did not match. Filtered in Dart now.
- [x] **The date field defaulted to yesterday** (`99c654a`). `toISOString()` is
      UTC, so east of Greenwich it returns the previous day all morning. Built
      from the local calendar now, shown as dd/mm/yyyy, and tapping it opens the
      native picker instead of asking you to type.
- [x] **The link only fired the share sheet** (`ccd3980`). Now a dialog with the
      URL visible, a Copy button, and Share. Copy must be its own tap: a
      clipboard write on web only works inside a live user gesture.

### 7. Groups — **done**

- [x] A group is a shared space with a title and more than one person on it. No
      new schema: identity already hung off the person, so somebody already in a
      one-to-one share keeps the PIN they set instead of collecting one per
      group.
- [x] **Group entries count immediately.** Waiting on the owner to approve a cab
      two other people shared would be absurd, so `status` there means "the
      owner has filed this in their own books", not "this is real".
- [x] That is why a group can be summed on the server when a pairwise share
      cannot: a group starts empty, so no history in anyone's Hive can
      contradict the total.
- [x] The page shows where you stand, where everyone else stands, and the fewest
      payments that clear it — the same greedy reduction as `simplifyDebts`.
- [x] Accepting generalises to N people, driven by the shares rather than by who
      submitted it. Tested, including somebody who paid without eating any of it.
- [x] App: "+ New group" on Debts, a per-member link with Copy and Share, and
      entries that involve you waiting in the group sheet.
- **Not done:** exact amounts inside a group (equal among whoever is ticked
      only). It needs a field per person; left until somebody wants it.

---

## What needs you, and when

Everything on the web side is **done and live**. What is left:

| What | Why it needs you |
|---|---|
| Cut the Android release | The APK is built locally and published under your account, and a release always waits for your explicit go |
| A real trial with a friend | Whether someone who has never heard of Lekha opens the link and understands it |
| Finish the PIN-reset test | One tap on "Allow reset" on Test's ledger — the last untested path |

## Android

**v1.2.0 is built and waiting.** `1.2.0+12`, signed with the release key
(CN=Kushal Girdhar), on the Desktop as `Lekha-v1.2.0.apk`. **Nothing is
published** — a release always waits for an explicit go.

**It will not install over the current app** — the signing key changed. Export
from Settings, uninstall, install, sign in; the cloud snapshot restores
everything.

No new dependencies were added anywhere in this work, which matters on this
machine: Gradle cannot fetch new artifacts through the TLS-inspecting proxy, so
a build that needs nothing new is a build that works.
