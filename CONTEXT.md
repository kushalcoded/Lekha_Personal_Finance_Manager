# Lekha — working context

A handoff for picking this project up cold: where things stand, how work gets
done on this machine, and what the user has decided. `PROGRESS.md` is the
feature log; `MEMORY.md` (gitignored) is the long-form project memory; the
`SETUP_*.md` files hold the Supabase steps. Last updated **2026-09-15**.

---

## Where things stand

| | State |
|---|---|
| Web (lekhamoney.app) | Live on `main`, deploys on every push via GitHub Pages (`gh run list`) |
| On `main`, unreleased | **v1.4.1** (`1.4.1+17`) — spread a payment across months in Insights. Not pushed, not released |
| Latest GitHub release | **v1.4.0** (`1.4.0+16`, released 2026-09-16 at `87de1bf`, same signing key) — money kinds, the everyday budget, cards, refunds, income, swipe nav, group delete, the Android resume fix, the stuck-notice fix. See PROGRESS §12 and §12a. Web live on the same commit; installed on the phone |
| Supabase | `detected_transactions.merchant` column added; `gemini-proxy` and `ingest-sms` redeployed with image + merchant support (2026-09-15). `share` unchanged |
| Tests | 295 logic tests pass, analyzer clean. Design goldens (26) drift daily — see Known issues |
| Devices | User's Android phone (Galaxy S20 FE, `SM_G781B`) still does SMS detection. The user is **moving to iPhone** and will use the web app in Safari there |

The last live check (2026-09-15, 20:41): phone and cloud both at 262 expenses,
same cloud version; Home shows the single summary card.

---

## Open threads

1. **Users must re-set their budget.** v1.4.0 changed it to mean everyday
   spending only; an old all-in figure overstates what is left. The release
   notes lead with this. The user already set theirs to ₹15,000.
2. **Not yet exercised on a device:** cards end to end, refunds, income entry,
   group delete. The stuck-notice fix is proven by a failing-then-passing test,
   not yet by adding a detected payment on the phone.
3. **Screenshot import** was used once and reported "10 already here". The
   message now says where each skipped payment is; the user has not re-tried.
   If it names expenses they never added, the same-day-same-amount matching in
   `lib/providers/sms/screenshot_import.dart` is too loose.
4. **Group split flow** has not been driven with a real member.
5. **Restore screen** has never been seen on a real reinstall.

## Ideas not yet started

- Tests for the guest page `web/s/index.html` (it has none; three bugs reached
  real guests through it).
- Pin the design-golden clock properly (see Known issues).
- Remove a member from a group; exact amounts for guests on the group page.

---

## How work gets done here

**Commands**
```
flutter analyze
flutter test --exclude-tags design        # logic tests
flutter test test/design_qc_test.dart     # goldens; --update-goldens to re-shoot
flutter build apk --release               # ~4 min, signed from android/key.properties
npx --yes deno check supabase/functions/<fn>/index.ts
```
Check a test run by its last line, not a pipe's exit code — `… | tail -1` hides
failures.

The real app on the `Pixel_7` AVD, from a fresh install through onboarding to
login; fails on any framework error (overflows included) and leaves
screenshots in `build/integration_screenshots/`. It clears the app's data
first, so it is pinned to `emulator-5554` — never point it at the phone.
```
bash test_driver/run_android.sh                # boot the AVD first; ~3 min
bash test_driver/run_android.sh <backup.json>  # + every tab and the add sheet
                                               #   on that data; ~5 min
```
It uses `flutter_driver`, not `integration_test`: the latter needs Gradle
downloads that Norton's SSL scanning blocks on this PC. For the same reason
debug builds read the engine from `~/flutter_mirror` (fetched with curl,
MD5-checked against Google's storage); the script sets
`FLUTTER_STORAGE_BASE_URL` to it. A Flutter upgrade changes the engine hash and
needs those jars fetched again.

The phone's real data on the emulator, cut off from the cloud: export a backup
on the phone (Settings → Export / share backup), then
```
bash test_driver/clone_to_emulator.sh <lekha_backup_….json>
```
`test_driver/clone.dart` restores it and treats the backup's user id as signed
in with **no Supabase session**, so every write is refused by RLS (logcat shows
`[sync] failed: … row-level security`, which is expected). `run_android.sh`
clears the app and leaves a driver build installed (its keyboard input is
emulated), so run this again before using the emulator by hand. No test account
is needed.

**Releases** (only after an explicit go): bump `version:` in `pubspec.yaml`,
build, verify with `apksigner verify --print-certs` (digest must be
`748f8027d71c15912deba83f511348dab420faf8d13eb526a250ae9c8ab920b3`), copy to the
Desktop as `Lekha-v<x>.apk`, then
`gh release create v<x> <apk> --target main --title "Lekha v<x>" --notes-file <notes>`.
Notes are written as symptoms users recognise. Never print `android/key.properties`.

**Edge Functions** are not deployed from git. The user pastes the file into the
Supabase dashboard. Order matters when a function writes a new column: run the
SQL first. Verify JWT: `gemini-proxy` **on**, `ingest-sms` and `share` **off**.

**The phone over adb** (`$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`)
- Wireless debugging's port changes whenever the phone sleeps; ask for the
  "IP address & port" at the top of the Wireless debugging screen.
- Pairing: the **user** runs `adb pair` and types the code — never enter the
  pairing code for them. In PowerShell the command needs `&` before the quoted
  path and `$env:LOCALAPPDATA`.
- From Git Bash, prefix device paths with `MSYS_NO_PATHCONV=1`
  (`adb push … /data/local/tmp/…`), then `adb shell pm install -r`.
- A black `screencap` means the screen is off or locked; the user must unlock.
- `adb logcat -d -s flutter | grep "\[sync\]"` shows every sync decision.
- Office Wi-Fi (`20.20.x`) blocked pairing once; home Wi-Fi (`192.168.1.x`) works.

**Commits** end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`;
imperative subject, body explains the symptom and the cause.

**Editing files**: bash heredocs mangle Dart strings with quotes and `\n`; write
Python patch scripts to the scratchpad and run them, asserting each anchor
matches exactly once. `dart format lib test` after.

---

## Architecture that matters for current work

**Sync** (`lib/services/sync/supabase_sync_service.dart`,
`snapshot_merge.dart`, `lib/services/storage/hive_service.dart`)
- One JSON snapshot per user in `user_backups`. `decide()`:
  no cloud → upload; dirty + cloud unchanged → upload; dirty + changed → merge;
  clean + changed → pull; clean + counts differ from cloud → pull (self-heal);
  leaving the app (`pushOnly`) never pulls.
- "Changed" = the cloud's `updated_at` is not the stamp this device last took in
  (`SyncState.remoteUpdatedAt`, compared with `isAtSameMomentAs`).
  `stampAfterSkip`: a skipped download must not advance that stamp.
- Dirty = the mutation marker exists; it carries a `seq` and is cleared only
  with the `seq` read before snapshotting.
- Uploads are compare-and-swap on the raw `updated_at` string; a refused write
  retries once.
- Merge: per-record clocks from the `sync_metadata` box (`recordClock` in the
  snapshot, deletions kept forever), per-key settings clocks, settlements
  unioned. Applied with `applyMergedSnapshot`, never `restoreFromBackup`.
- Settings → tap the Sync row → **Sync details** (what the last sync saw).

**Groups** (`lib/providers/share/share_providers.dart`)
- A group is a `shared_spaces` row with a title. Splitting an expense with a
  group picked (`SplitConfig.groupId`) books pairwise debts as always and posts
  the bill with `publishSplit` — id `groupEntryIdFor(expenseId)`, upsert,
  offline queue in `kLocalPrefsBox`.
- `pairwiseView` keeps group bills off one-to-one pages. Shares use the space's
  `owner_name`. `_syncSpace` lookups must filter `shared_spaces.title is null`.
- "Record a payment" publishes settlement rows to affected groups; accepting a
  guest settlement settles between payer and receiver (`settlementWith`).

**Money kinds** (`lib/models/category/category_kinds.dart`, 2026-09-16)
- Every `ExpenseCategory` carries a `CategoryKind`: everyday · committed ·
  investment · transfer · income. `countsAsSpent` = everyday + committed, and
  `Iterable<Expense>.spendable(kinds)` is how every total asks.
- **The budget the user sets is the everyday allowance.** Bills are shown but
  never subtracted from it — `everydayLeft = budget − everydaySpent` is the Home
  hero. Everything measured against the budget (`remaining`, `percentSpent`,
  `isOverBudget`, the burn rate, the figure given to the AI) must use everyday
  spending, or the screen shows two answers to one question.
- `committedPlanned` only says what is still due this cycle, on the Bills row.
- **Spread payments (1.4.1) are charts-only.** `spreadForCharts` cuts a spread
  expense into monthly slices for `analyticsScopedAllProvider` and the monthly
  bars, and nowhere else. It must run *before* the window is applied, and must
  drop slices dated after now, because Insights windows have no upper bound.
- Insights panels and Home's category bars are **everyday-only**: with bills in,
  the answer was "Rent" every month. Bills live in the "Where the money went"
  section, which is the one place the whole division is shown.
- Refunds are negative-amount expenses; income is an expense in an income-kind
  category (Spent/Received switch in the add sheet); a card balance is
  spending-minus-transfers on that method, all time.
- Cards live in Debts (`card_ledger_screen.dart`); their statement days are a
  separate `cards` settings key — never reshape `paymentMethods`.
- Filter once in `analyticsScopedExpensesProvider`; never filter
  `cycleExpensesProvider` or the expense-list stats.

**Detected payments** — SMS (Android receiver, iPhone via `ingest-sms`) and
payment screenshots (Gemini vision through `gemini-proxy`) feed one Detected
list. Screenshot rows are `shot_…` ids and never `provisional`.
`PendingTransaction.merchant` shows on cards only and is cleared on add/dismiss.

**Navigation**: the phone layout pages between tabs (`PageView` in
`app_shell.dart`); desktop keeps a switch and keys 1-4. On Insights the pager
takes `NeverScrollableScrollPhysics` and the screen owns the gesture: a swipe
steps through Cycle → 30 days → 12M and only carries on to the next tab at the
edge. Two drag recognisers competing for one gesture is a coin toss, so only
ever let one of them have it.

**UI**: all messages go through `showNotice` (`lib/widgets/common/top_notice.dart`,
top of screen). Sync buttons use `syncWithFeedback`. Home has one summary card:
AI points (`dashboardAiSummaryProvider`, JSON items with tone/target), falling
back to the app's reminders. Chart axis labels use `axis_labels.dart`.

Design system: Midnight Terminal — ground `#0A0A0D`, surface `#131318`,
surface-2 `#1A1A21`, accent `#9083F0`, positive `#46C98B`, negative `#F2555A`,
warning `#F0A13B`. No gradients, blur or glow.

---

## What the user has decided

- **Every GitHub release needs an explicit go.** "Build" is not "release".
- Merchant names are shown on detected cards but **not** put into the expense
  note, and not stored after the card is decided.
- Home keeps the **AI summary**; Needs Attention was removed.
- Sync merges record by record when both devices changed things.
- In the split sheet, pick a group and members; adding a non-member asks to add
  them to the group. Past splits can be moved into a group.
- iPhone will use the web app, not a native build.
- Asked to be consulted on real decisions; prefers the lazy, minimal fix that
  is correct at the root.

## Known issues

- **Design goldens go stale every day**: the harness seeds data relative to the
  real clock (cycle start "12 days ago" prints an absolute date), so ~9 shots
  differ by a few dozen pixels the next morning. Not caused by feature changes.
