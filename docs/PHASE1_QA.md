# Phase 1 QA checklist — `vll_sms` + Laravel API + SMSver1

## Prerequisites

- Laravel API (`vll_backend`) reachable from the device/emulator.
- Base URL (no trailing slash), e.g. `http://10.0.2.2:8000` (Android emulator → host).
- Valid SMSver1 user in Laravel `users` table with MD5-stored password matching portal login.
- User `contact_phone` populated where possible (sender binding + inbound sync use this).

## Auth

| Step | Expected |
|------|----------|
| Login with portal username/email + password | 200, Sanctum token stored |
| Session restore on cold start | `/api/user` succeeds → stays logged in |
| Logout | Token revoked server-side (when supported); local token cleared |

## Sender IDs

| Step | Expected |
|------|----------|
| GET `/api/senders/list` after login | JSON `data.senders` listed in Home + Compose |
| Bind sender | POST `/api/sender-pointers/bind` succeeds; pointer stored against portal phone |

## Compose (immediate send)

| Step | Expected |
|------|----------|
| Terms unchecked | Send blocked with validation |
| Repeat ≠ None | Blocked with message to use portal |
| Valid `from` / message / `to` | POST `/api/sms` → 200/201; row in local `outbound_messages` |

## Inbound listener (Android)

| Step | Expected |
|------|----------|
| Grant SMS permission | Listener starts |
| Notification | “VLL SMS — Listening…” ongoing notification |
| Incoming SMS | Row in local DB + POST `/api/interact`; sync chip Pending→Synced |
| Airplane mode / offline | Pending + `last_error`; auto-retry ~45s |

## Reply flow

| Step | Expected |
|------|----------|
| Tap inbox row | Opens Compose with recipient prefilled |

## Pilot rollout notes

- Confirm production API URL via secret tap → Admin PIN → Base URL.
- Legal: SMS monitoring consent shown once on Home (dialog).
- Rate limiting and social APIs deferred to later phases.
