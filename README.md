# Lekha — offline-first money & debt tracker

**Lekha** (लेखा — "ledger") is a privacy-first personal finance app for Android.
It works fully offline out of the box, auto-captures spends from your bank SMS,
tracks who owes whom, splits bills, and (optionally) syncs across your devices —
all wrapped in a calm, dark, single-purpose interface.

> No account required. Your data lives on your phone. Cloud sync is opt-in.

<!-- Add screenshots here: docs/screenshots/*.png -->

---

## Why

Most expense apps either want a login before you can add a chai, or ship your
transactions to a server by default. Lekha flips that: it's **local-first**,
does the tedious data entry **for** you (bank/UPI SMS → parsed expense), and only
talks to the cloud if you explicitly sign in to back up and sync.

## Features

- **Offline-first** — full functionality with zero setup, no account, no network.
- **Salary-cycle budgeting** — separate salary and budget per cycle; a manual
  reset archives the finished cycle into a frozen history snapshot.
- **SMS auto-detect** — an on-device receiver catches bank/UPI debit texts and an
  AI pass extracts the amount, so spends land as *pending* cards you confirm,
  dismiss, or merge (several texts → one expense).
- **Debts done right** — receivables & payables collapsed into a **per-person net
  balance**, with **partial settlements** and gentle, **AI-drafted reminders**
  (English / Hinglish / Hindi) shareable over WhatsApp or SMS.
- **Bill splitting** — split an expense across people; each share aggregates into
  that person's running balance (grouped, not duplicated).
- **Analytics** — spending charts plus optional AI insight cards.
- **Voice & widget quick-add** — add an expense by speaking, or from a
  home-screen widget.
- **Backup** — export/import the entire app state as a single JSON file.
- **Optional cloud** — Supabase email + Google sign-in with whole-account
  snapshot sync across devices. Sign-in is skippable; sign-out keeps your data
  local.

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

## Getting started

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

### Optional configuration (`.env`)
The app runs fully offline with an empty `.env`. To enable the optional
features, add:

| Key | Enables |
|-----|---------|
| `GEMINI_API_KEY` | SMS parsing, AI insights, AI debt reminders |
| `GEMINI_MODEL` | (optional) model override |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | cloud auth + cross-device sync |

Cloud auth + sync setup (Google OAuth, the sync table, RLS) is documented in
[`SETUP_AUTH.md`](SETUP_AUTH.md).

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
