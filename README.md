# imartListener

Flutter app for **iMart SMS Business Desk** — capture customer SMS and WhatsApp on a business phone, view an Inbox, reply manually (template or compose, individual or bulk), and run social phone lookups.

Part of the iMart stack: works with [imart-api](https://github.com/imartgroup/imart-api) and [imartPortal](https://github.com/imartgroup/imartPortal).

---

## Features

| Tab | What it does |
|-----|----------------|
| **Home** | Desk KPIs, bind Sender ID, listen filters, shortcuts |
| **Inbox** | All captured SMS + WhatsApp; multi-select → Reply |
| **Reply** | Templates + compose → send to one or many selected numbers |
| **Social** | Phone lookup (Instagram, Facebook, WhatsApp, Google, etc.) |

Additional screens: **SMS settings** (Sender ID CRUD, desk toggles, gateway status read-only).

---

## Platforms

| Platform | Capture | Reply |
|----------|---------|-------|
| **Android** | Full SMS + WhatsApp (notification access) | SMS via API; WhatsApp logged |
| **Web** | No live capture (dev/UI demo) | Yes, if API reachable |
| **iOS** | Not primary target in this release | Limited |

Production capture runs on **Android** on the phone that receives business SMS/WhatsApp.

---

## Requirements

- Flutter SDK ≥ 3.3 (`dart` ≥ 3.3)
- Running [imart-api](https://github.com/imartgroup/imart-api) (Laravel)
- Client account created in portal (`php db/seed_portal_roles.php`)

---

## Install & run

```bash
git clone https://github.com/imartgroup/imartListener.git
cd imartListener
flutter pub get
```

### Local API (Chrome / desktop)

```bash
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000
```

### Android emulator → host machine API

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8000
```

### Physical Android on same Wi‑Fi

Use your PC LAN IP, e.g.:

```bash
flutter run --dart-define=API_BASE=http://192.168.1.10:8000
```

### Release web build

```bash
flutter build web --release --dart-define=API_BASE=https://your-api.example.com
```

Serve the `build/web/` folder (Apache, Nginx, or `flutter run -d web-server`).

---

## Login (local test)

| User | Password | Role |
|------|----------|------|
| `imart` | `ImartListen123!` | Client |
| `imartadmin` | `ImartAdmin123!` | Admin (API; portal for admin UI) |

Change these in production.

---

## First-time setup (client)

1. **Login** with client credentials.
2. **SMS settings** → **Add Sender ID** (e.g. `iMart SMS`). Must match an Active sender in portal/API for your account.
3. **Home** → **Capture setup** → select Sender ID → **Bind Sender ID**.
4. **Android permissions**:
   - SMS read/receive
   - Notification access (for WhatsApp capture)
5. Optional: **Listen filter chips** on Home — file captures under specific Sender IDs when one phone serves multiple brands.
6. Send a test SMS to the device → check **Inbox** (status **Portal OK** when synced).

---

## How capture works

1. **SMS (Android):** `readsms` listens to all incoming SMS on the device.
2. **WhatsApp:** Android notification listener (skips duplicate SMS notifications).
3. Message saved to **local SQLite** → shown in Inbox immediately.
4. App posts to `POST /api/v1/interact` with auth token.
5. API stores row in `incoming` → visible in portal **Conversations**.

**Important:** The app does not filter which SMS arrive on the phone. **Sender ID binding / listen filters** only control how messages are **filed on the server**. Without a bound Sender ID (or valid listen filter), sync fails and Inbox shows **Pending sync**.

---

## Reply workflow

### From Inbox (recommended)

1. Open **Inbox** → tap checklist icon (or long-press a row).
2. Select one or more captured messages.
3. Tap **Reply to N numbers**.
4. On **Reply** tab: pick a **template** or type in **Compose**.
5. **Send individual SMS** (1 selected) or **Send bulk SMS** (2+).

### Templates

- **Reply → Templates** tab: create, edit, delete templates.
- Optional **auto-reply on capture** (toggle + template) — uses API gateway from `.env`.

---

## Social lookup

1. Open **Social** tab, or tap search icon on an Inbox row.
2. Enter or use prefilled customer phone.
3. Choose platform chips → open search links or run API check.
4. History syncs to portal **Social lookups**.

---

## Configuration

| Setting | Where |
|---------|--------|
| API URL | Compile-time `API_BASE` (`--dart-define`) |
| Auth token | Stored in `shared_preferences` after login |
| Listen filters | Home chips + `listen-filters` API |
| Local inbox cache | SQLite `vll_sms.db` on device |

No SMS gateway secrets in the app — only Sender ID selection.

---

## Project structure

```
lib/
  auth/           Login, session
  system/         Main shell, Home, Inbox, Reply, Social, SMS settings
  services/       SMS listener, sync, notifications, desk selection
  data/           Local SQLite
  packages/       API client
  shared/         Constants, branding, themes
android/          Notification capture native bridge
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Home “Capture setup” spins forever | Ensure API is up; add Sender ID in SMS settings |
| Inbox **Pending sync** | Bind Sender ID on Home; check login token and API URL |
| No WhatsApp in Inbox | Enable Notification access in Android settings |
| Web shows old UI | Hard refresh; rebuild with `flutter build web` |
| API connection failed on phone | Use LAN IP or `10.0.2.2` for emulator; not `127.0.0.1` |

---

## Build version

See `pubspec.yaml` (`version:` field). Current desk release: **1.4.x**.

---

## Related repos

- [imartPortal](https://github.com/imartgroup/imartPortal) — web desk
- [imart-api](https://github.com/imartgroup/imart-api) — Laravel backend
- [Platform overview](https://github.com/imartgroup/imart-sms-desk) — full stack README
