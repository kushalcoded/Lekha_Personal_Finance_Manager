# Lekha — project memory

Personal finance app (expenses, debts/splits, SMS auto-detect, AI assistant).
Ships as an **Android APK** and a **PWA at lekhamoney.app**. Single-user in
practice, open source, one maintainer.

Current version: **1.1.2+6**. Published releases: v1.0.0, v1.0.2, v1.1.0.

---

## 1. Tech stack & versions

| Area | Choice |
|---|---|
| App | Flutter / Dart. Pubspec name `personal_expanse_tracker` (typo is load-bearing — imports use it). Display name **Lekha** |
| State | `flutter_riverpod` 2.6.1 — `StateNotifierProvider`, `Provider`, `FutureProvider` |
| Local store | `hive` 2.2.3 + `hive_flutter`. Boxes: `expenses`, `receivables`, `payables`, `recurring_templates`, `app_settings`, `monthly_budgets`, `pending_transactions`, `sms_seen`, `local_prefs`, `local_backups`, `sync_metadata`, `sync_state`, `onboarding` |
| Backend | Supabase — Postgres, Auth (email + Google), Edge Functions (Deno). **Free tier** |
| AI | Gemini (`gemini-3.1-flash-lite`) via the `gemini-proxy` Edge Function; Groq (`llama-3.3-70b-versatile`) fallback. Keys never ship in clients |
| Charts | `fl_chart` 1.2.0 |
| Fonts | Bundled variable TTFs in `assets/fonts`: **Inter**, **Space Grotesk**, **JetBrains Mono**. Not `google_fonts` at runtime |
| Notable pins | `package_info_plus` ^10.2.1 (v8 conflicts with `share_plus` 13 → win32) |
| Other | `share_plus`, `url_launcher`, `speech_to_text`, `home_widget` (Android only), `flutter_slidable`, `intl` |

Supabase tables: `user_backups`, `detected_transactions`, `ingested_sms`,
`ingest_tokens`, `ai_usage`. (`expenses`/`receivables`/`payables`/
`recurring_templates` tables were dead leftovers — **dropped**.)

---

## 2. Architecture & patterns

**Folders:** `lib/{core,models,providers,screens,services,theme,utils,widgets,navigation}`.
Screens own their subtree: `screens/<feature>/{providers,widgets,utils}/`.
Shared UI in `widgets/common/` (`form_bits.dart`, `glass.dart`, `ai_text.dart`).

**Sync is whole-snapshot, not per-entity.** One JSON blob per user in
`user_backups`, last-write-wins. Per-entity sync was tried first and kept
losing newly-added fields. The snapshot is the same structure Export/Import
uses, so a restore is a true clone.

Sync rules that must not be broken:
- **All sync operations serialize through one lock** in `SyncNotifier`
  (`_serialize`). `syncNow` additionally coalesces repeat taps onto the
  in-flight run; `forcePush`/`forcePull` queue behind it.
- **`createLocalBackupSnapshot` throws while a restore is in progress** — a
  restore clears boxes before refilling, and snapshotting mid-clear is how
  data got erased.
- **A push carrying zero money records is refused** when the cloud has some.
- A pull that would reduce record count **saves a local backup first**.
- `lastLocalMutationAt` (in-memory, not persisted) marks "this device has
  unpushed edits" and makes sync push instead of pull. **Only real money
  edits may set it** — see Known Issues.

**Detections live outside the snapshot.** `detected_transactions` is its own
table because (a) LWW would drop them and (b) iOS needs them created without
the app running. Each device pulls the table, pushes its own detections, and
status changes propagate with *terminal beats pending*.

**SMS pipeline:**
- Android: native `SmsReceiver.kt` → SharedPreferences queue → MethodChannel
  `lekha/sms` → parsed on-device → Hive → pushed to `detected_transactions`.
- iOS: Shortcuts automation POSTs to `ingest-sms`, which **parses server-side
  on arrival** and writes to `detected_transactions`. Unparseable rows stay
  `status='new'` so the app's own drain remains the fallback.
- Foreground poll is 5s (local queues only); **cloud round-trips throttled to
  60s**, or immediate on resume / manual sync (`sync(force: true)`).

**Cycle scoping:** `cycleExpensesProvider` filters `!date.isBefore(cycleStart)`.
The Expenses list and every cycle total derive from it, so anything dated
before the cycle start **saves but is invisible** — the single most common
source of "it didn't save" confusion. Add and Edit sheets warn via
`OutOfCycleNote`.

**Salary cycle never moves on its own.** `salaryDay` (1–31, optional) only
decides *when to ask*; a dashboard prompt offers a date picker defaulting to
that day but accepting any date, because credits drift early and late.

---

## 3. Non-obvious commands & setup

```bash
flutter analyze
flutter test --exclude-tags design        # 60 tests; goldens excluded
flutter test test/design_qc_test.dart --update-goldens   # render 16 screens to PNG
flutter build apk --release               # then copy to Desktop as Lekha-v<ver>.apk
```

- **Web deploys itself** on push to `main` (GitHub Actions → Pages,
  `--base-href /`). ~3–5 min, then hard-refresh.
- **Edge Functions are NOT deployed from git.** They run whatever was pasted
  into the Supabase dashboard — redeploy manually after editing.
  `ingest-sms`: **Verify JWT OFF**. `gemini-proxy`: **Verify JWT ON**.
- **SQL lives in `SETUP_IOS_SMS.md`**, written to be re-runnable (`drop policy
  if exists` before each create).
- **Releases are published by the user only** (needs their GitHub auth). APKs
  must be **built on this PC** — a CI-built APK has a different signature and
  breaks in-app updates.
- The design harness renders real screens with seeded Hive data + real fonts;
  it needs the MaterialIcons font from the Flutter SDK cache or icons render
  as tofu.

**Shell:** PowerShell mangles embedded `"` in `git commit -m` and mojibakes
UTF-8 (₹). Use the Bash tool with a heredoc for commit messages, and
bash/python for text surgery on source files.

---

## 4. Active decisions & rationale

- **Whole-snapshot sync** — per-entity sync silently dropped new fields.
  Accepted ceiling: simultaneous offline edits on two devices lose one side.
- **Detections in their own table** — survives LWW; lets the server create
  them for iOS.
- **Server-side SMS parsing for iOS** — nothing of ours can run in the
  background on iOS, so client-side parsing meant days of delay.
- **Salary day prompts, never auto-rolls** — salary credits arrive early and
  late; a fixed auto-roll would be wrong most months.
- **Design system "Midnight Terminal"** (locked, fully implemented):
  ground `#0A0A0D`, surface `#131318`, surface-2 `#1A1A21`, text `#EDEDEF`,
  muted `#8A8F98`, accent violet `#9083F0`, positive `#46C98B`, negative
  `#F2555A`, warning `#F0A13B`, hairline white 7%.
  - **Violet means "tappable" — never decoration.** Charts are the one
    sanctioned exception (accent series, 32% history bars + full current).
  - Accent fills take **dark** text (`#0A0A0D`); white on violet fails contrast.
  - **Space Grotesk is rationed to 3 roles**: money hero, screen titles
    (AppBar `titleTextStyle`), stat values. Inter everywhere else.
    JetBrains Mono for 10px uppercase data labels (`FieldLabel`).
  - Radii 16 sheets/dialogs · 12 cards · 10 buttons · 8 inputs · 999 pills.
  - **Banned: blur, gradients, glow, sparkle icons.**
  - Category tints are their own family (amber/teal/sky/tan/purple…), no
    violet; legacy hexes remap at render time in `CategoryStyles.parseHex`.
- **Material *outlined* icons instead of Lucide** — same thin-line language,
  zero new dependency.
- **Goldens excluded from the default test run** — font/platform sensitive.
- **AI metering fails open** — `AI_DAILY_LIMIT` (set to 200) via `ai_usage` +
  `increment_ai_usage` RPC; a metering outage must not block the app.

---

## 5. Known issues & workarounds

| Issue | Root cause / fix |
|---|---|
| **`LayoutBuilder` inside `IntrinsicHeight` collapses to 0 height in release** (throws only in debug) | Use plain bool flags (`AnalyticsSection.stretch`, `_SettingsGroup.stretch`). Guarded by `test/analytics_layout_test.dart` |
| **`styleFrom(textStyle:)` REPLACES `labelLarge`** | Drops `fontFamily`, so buttons fell back to the platform font. Always repeat `fontFamily: 'Inter'` |
| **fl_chart edge axis labels paint outside the card** | Wrap in `SideTitleWidget` with `fitInside: SideTitleFitInsideData.fromTitleMeta(meta)` |
| **`create policy` is not idempotent** | Re-running the setup SQL dies on `42710`, and because the editor runs one transaction, *nothing* commits. `drop policy if exists` first |
| **Detections marked the account dirty** | `savePendingTransaction` called `_notifyChanged()`, so *receiving* a detection made the device push instead of pull — devices diverged silently. It must not notify. Pinned by `test/pending_dirty_flag_test.dart` |
| **iOS Shortcuts automations disable themselves silently** | Settings row surfaces staleness ("no SMS for N days") from `iphoneSmsHealthProvider` |
| **Browser-pane screenshots fail when the pane is hidden**; sign-in also blocks logged-in flows | Use the golden render harness instead — it renders real screens with seeded data |
| **Claude cannot create accounts / enter passwords / publish releases** | Policy + auth. Those steps are always handed to the user |
| Recurring-generated expenses dated `nextDueDate` can land outside the cycle | Known, unfixed — user doesn't use the feature. Options discussed: footer listing out-of-cycle expenses |
| `analytics_providers.dart` keeps a private `_inferPaymentMethod` duplicate | Correct, but duplicated. Unify if it ever drifts |
| Leaked-password protection unavailable | Supabase **Pro-only**. Free alternatives applied: min length, password requirements, secure password change |

---

## 6. Code style rules

- **Comments explain *why*, never *what*.** Every non-obvious guard carries
  the failure it prevents (e.g. "snapshotting mid-clear is how data was
  erased"). Delete comments that restate the code.
- **A rule lives in exactly one function.** Payment-method resolution was
  open-coded in four places and one got it wrong; it is now
  `expensePaymentMethod(Expense)`. Same for `OutOfCycleNote`, `SmsActionPill`.
- **Non-trivial logic leaves one runnable check.** Regression tests state the
  original failure in a comment so the invariant isn't "optimised away" later.
  Date/boundary logic (month clamping, cycle rolls) always gets tests.
- Run `dart format` on touched files; `flutter analyze` must be clean before
  commit.
- Private widgets `_Foo` live in the screen file; anything reused moves to
  `widgets/common/`.
- **Network/offline failures swallow silently and retry next sync** — with a
  comment saying so. Metering and health checks **fail open**.
- Git commits: imperative subject, body explains the *symptom* and the cause,
  no embedded `"` (PowerShell), and end with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- Release notes are written as **symptoms users recognise**, not changelog
  internals ("syncing repeatedly could erase expenses", not "added a
  re-entrancy guard").
