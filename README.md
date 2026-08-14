# imartListener

**iMart SMS Business Desk — Android listener app**  
Copyright © iMart Group Ltd · Product engineering mirror: [SarahGordon895](https://github.com/SarahGordon895)

---

## Corporate brief

**imartListener** is the mobile capture arm of the **iMart SMS Business Desk**. It runs on the business Android phone that receives customer SMS and WhatsApp, applies **portal-managed listen filters**, stores matching messages in a secure Inbox, and syncs them to **imartPortal** for desk reply, audit, and social phone verification.

Together with the Laravel **API** and the PHP **portal**, it gives enterprises a controlled listen → filter → reply loop without exposing gateway credentials on the handset.

| Role | Product |
|------|---------|
| Capture & reply on device | **imartListener** (this repo) |
| Configure filters & desk | [iMartListenerportal](https://github.com/SarahGordon895/iMartListenerportal) |
| Auth, sync, SMS gateway | [vll-backend](https://github.com/SarahGordon895/vll-backend) |

---

## Live URLs

| Service | URL | Notes |
|---------|-----|--------|
| **Listener API (primary)** | https://listenerapi.lipapay.co.tz | Default production API for the app |
| **API (iMart)** | https://api.imartgroup.co.tz | Alternate / legacy API host |
| **SMS API** | https://sms-api.imartgroup.co.tz | Alternate API virtual host |
| **Portal / SMS desk** | https://sms.imartgroup.co.tz | Web desk + app update feed |
| **App update JSON** | https://sms.imartgroup.co.tz/app-update.json | In-app update check |
| **Reachable fallback** | http://162.220.11.235 | IP fallback when DNS differs |

Local development API: `http://127.0.0.1:8000`

---

## What the app does

| Area | Capability |
|------|------------|
| **Listen** | Captures inbound SMS; WhatsApp via Android notification access |
| **Filter** | Applies portal settings: unique keywords, From numbers, filing Sender IDs |
| **Inbox** | Local + synced thread list; multi-select for reply |
| **Reply** | Templates or compose; individual / bulk SMS via API |
| **Social** | Phone lookup for listened senders (Facebook, Instagram, WhatsApp, Google, …) |
| **Sync** | Portal filters refresh on login, resume, and ~every 60 seconds |

Portal is the **only** place to change listen filters. The app syncs them read-only and stores only matching traffic.

---

## Product flow

```text
Customer SMS / WhatsApp
        ↓
  imartListener (Android)
        ↓  portal filters (keyword · From · Sender ID)
  Inbox (device)  ──sync──►  API  ──►  imartPortal Conversations
        ↓                                    ↓
   Reply on phone                     Reply on web desk
        ↓                                    ↓
              SMS gateway (API .env only)
```

---

## Repositories (SarahGordon895)

| Component | GitHub |
|-----------|--------|
| App | https://github.com/SarahGordon895/vll_sms · https://github.com/SarahGordon895/imartlistenerApp |
| Portal | https://github.com/SarahGordon895/iMartListenerportal |
| API | https://github.com/SarahGordon895/vll-backend |

Organisation mirrors: [ImartListener](https://github.com/iMartGroup-Limited/ImartListener) · [ImartPortal](https://github.com/iMartGroup-Limited/ImartPortal) · [Imart-api](https://github.com/iMartGroup-Limited/Imart-api)

---

## Platforms

| Platform | Capture | Reply |
|----------|---------|-------|
| **Android** | Full (SMS + WhatsApp notification access) | SMS via API |
| **Web** | UI / demo only | If API reachable |
| **iOS** | Not primary in this release | Limited |

Production capture: **Android** on the published business number.

---

## Build & run

```bash
git clone https://github.com/SarahGordon895/vll_sms.git
cd vll_sms
flutter pub get

# Point at live API
flutter run --dart-define=API_BASE=https://listenerapi.lipapay.co.tz

# Or local API
flutter run --dart-define=API_BASE=http://127.0.0.1:8000

# Release APK (prod flavour)
flutter build apk --release --flavor prod
```

Output: `build/app/outputs/flutter-apk/app-prod-release.apk`

---

## Support

| | |
|--|--|
| **Company** | iMart Group Ltd |
| **Tanzania** | +255 742 200 333 |
| **Kenya** | +254 111 25 25 21 |
| **Email** | support@imartgroup.co.tz |

---

## License & ownership

Proprietary software of **iMart Group Ltd**.  
Engineering workspace and documentation mirrors under **SarahGordon895** are for delivery and operations; production brand and live services remain iMart Group.
