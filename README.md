# Lekha — offline-first money & debt tracker

**Lekha** (लेखा — "ledger") is a privacy-first personal finance app for
**Android and the web** (installable on iPhone as a PWA). It stores everything
on your device first, auto-captures spends from your bank SMS, tracks who owes
whom, splits bills, and syncs across all your devices through your account —
all wrapped in a calm, dark, single-purpose interface.

> Local-first storage, one sign-in (Google or email), every device in sync.

**▶ Try it now:** https://kushalcoded.github.io/Lekha_Personal_Finance_Manager/

<!-- Add screenshots here: docs/screenshots/*.png -->

---

## Why

Most expense apps make data entry a chore and treat your transactions as their
product. Lekha is **local-first** — the app reads and writes on-device storage
first, so it's instant and works offline — and does the tedious data entry
**for** you (bank/UPI SMS → parsed expense). Your account exists for exactly
one reason: backing up and syncing **your** data across **your** devices.

## Features

- **Local-first** — instant on-device storage (works offline after sign-in);
  your account backs everything up and mirrors it across devices.
- **Salary-cycle budgeting** — separate salary and budget per cycle; a manual
  reset archives the finished cycle into a frozen history snapshot.
- **SMS auto-detect** — an on-device receiver catches bank/UPI debit texts and an
  AI pass extracts the amount, so spends land as *pending* cards you confirm,
  dismiss, or merge (several texts → one expense). On **iPhone**, a Shortcuts
  automation forwards bank SMS into the same pipeline
  (see [`SETUP_IOS_SMS.md`](SETUP_IOS_SMS.md)).
- **Debts done right** — receivables & payables collapsed into a **per-person net
  balance**, with **partial settlements** and gentle, **AI-drafted reminders**
  (English / Hinglish / Hindi) shareable over WhatsApp or SMS.
- **Bill splitting** — split an expense across people; each share aggregates into
  that person's running balance (grouped, not duplicated).
- **Analytics** — spending charts plus optional AI insight cards.
- **Voice & widget quick-add** — add an expense by speaking, or from a
  home-screen widget.
- **Backup** — export/import the entire app state as a single JSON file.
- **Cross-device sync** — Supabase email + Google sign-in; the whole account
  syncs as one snapshot, pushed ~10s after every edit. Sign-out keeps your
  data on the device.

## Tech stack

Flutter · Riverpod · Hive · fl_chart · Supabase (auth + Postgres) ·
Google Gemini API · speech_to_text · home_widget · Kotlin (SMS receiver)

## Architecture highlights

- **Offline-first with optional sync** — everything is keyed to a local user id
  and works without a backend; signing in migrates local data into the account.
- **Snapshot sync** — the whole account travels as one JSON snapshot per user
  (simple, lossless, last-write-wins) instead of brittle per-table sync.
- **Native SMS bridge** — a Kotlin `BroadcastReceiver` queues incoming SMS;
  Dart drains the queue over a `MethodChannel` and parses debits AI-first, with
  amount+time de-duplication.
- **Typed Hive storage** with backwards-compatible migrations.

## Install

### Web / iPhone (PWA)

Open **https://kushalcoded.github.io/Lekha_Personal_Finance_Manager/** — on
iPhone, use Safari → Share → **Add to Home Screen** for a full-screen app.
Sign in on iOS so your data is backed by cloud sync (Safari can evict local
browser storage for long-unused sites).

### Android (APK)

Grab the latest APK from the
[**Releases**](https://github.com/kushalcoded/Lekha_Personal_Finance_Manager/releases/latest)
page and install it on any Android device:

1. Download `Lekha-vX.Y.Z.apk`.
2. Open it — Android will ask to allow installing from this source; approve it.
3. Launch **Lekha**. No account or setup needed.

> The release APK is signed with a debug key (fine for sideloading). Android
> may show an "unknown app" prompt — that's expected for apps outside the Play
> Store.

## Getting started (build from source)

### Prerequisites
- Flutter SDK (Dart 3.x)
- An Android device or emulator

### Run
```bash
git clone https://github.com/kushalcoded/Lekha_Personal_Finance_Manager.git
cd Lekha_Personal_Finance_Manager
cp .env.example .env      # optional keys; app runs without them
flutter pub get
flutter run
```

### Configuration (`.env`)

| Key | Enables |
|-----|---------|
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | auth, cross-device sync, AI features |

AI (SMS parsing, insights, debt reminders) runs through a JWT-verified
`gemini-proxy` Edge Function, so the Gemini key lives server-side and never
ships in the app. Backend setup (Google OAuth, sync table, RLS, AI proxy) is
documented in [`SETUP_AUTH.md`](SETUP_AUTH.md); iPhone SMS capture in
[`SETUP_IOS_SMS.md`](SETUP_IOS_SMS.md).

> `.env` is git-ignored — never commit real keys.

## Project layout

```
lib/
  models/        Hive + domain models
  providers/     Riverpod state (auth, storage, sms, sync, ai)
  screens/       feature UIs (expenses, debts, analytics, settings, auth …)
  services/      storage (Hive), sync (Supabase), gemini, auth
  widgets/       shared UI (glass cards, form bits)
android/app/src/main/kotlin/…  SMS receiver + home-widget provider
```

## Scope & limitations

- **Android-only**, **dark-only** — by design.
- Cloud sync is **whole-snapshot last-write-wins**: ideal for one person across
  a couple of devices used one at a time.

## Roadmap

- [ ] Broader widget/provider test coverage
- [ ] Screenshots + a short demo GIF
- [ ] Per-record sync merge (only if concurrent multi-device editing needs it)

## Contributing

Issues and PRs welcome. Please run `flutter analyze` and `flutter test` before
opening a PR, and keep changes focused. For larger features, open an issue to
discuss first.

## License

[MIT](LICENSE) © 2026 Kushal Girdhar
