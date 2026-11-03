# CLAUDE.md — Vyapari

Read this file first in every session. Full details live in `docs/`.

## What we are building

**Vyapari** is an Indian-themed property trading board game (Monopoly-style mechanics, original name, art and card text) for 2–8 players.

- **Local mode (Mini Militia style):** one phone hosts the game server inside the app; others join over the same Wi-Fi or the host's hotspot. No internet needed.
- **Online mode:** the same server code runs in Docker (home lab or cloud); players join by room code.
- **Voice only:** push-to-talk voice clips (walkie-talkie). No typed chat anywhere.
- **Platforms:** Android, iOS, web (web is join-only, online server only).
- **Release:** internal use first. No ads, no payments.

## Documents

| File | Contents |
| --- | --- |
| `docs/requirements.md` | Functional and non-functional requirements (IDs like FR-GAME-3) |
| `docs/design.md` | Architecture, packages, data model, protocol, flows, screens, scaling |
| `docs/backlog.md` | 40 stories in 8 waves with build steps, tests and acceptance criteria |

## Tech stack

- Language: **Dart** everywhere. App: **Flutter** (Android, iOS, web). State: **Riverpod**.
- Server: `shelf` + `shelf_web_socket`; one WebSocket per player (JSON game messages, binary voice frames).
- Discovery: UDP broadcast + mDNS (`multicast_dns`); QR via `qr_flutter` / `mobile_scanner`.
- Voice: `record` (Opus on Android/web, AAC on iOS) + `just_audio`.
- Storage: JSON save files (local), SQLite (online). Tests: `dart test`, Flutter integration tests, GitHub Actions.

## Repository layout

```
vyapari/
├── packages/
│   ├── core/       # pure Dart: models, rules engine, dice, bots (NO Flutter, NO dart:io)
│   ├── protocol/   # message classes + JSON codecs + voice frame format
│   ├── server/     # rooms, sessions, WebSocket hub, voice relay, discovery
│   └── app/        # Flutter UI
├── assets/boards/india/   # board.json, cards.json, art
├── server_bin/            # main.dart for the Docker online server
├── docs/                  # requirements.md, design.md, backlog.md
└── test/                  # cross-package simulations
```

## Hard rules (never break these)

1. **Server is the single source of truth.** Clients send intents only (`roll`, `buy`, `trade_propose`…). Only the rules engine changes money, ownership or position.
2. **`packages/core` stays pure.** No Flutter, no `dart:io`, no network, no clocks or randomness except through injected interfaces.
3. **Rules engine is a reducer:** `apply(action, state) -> (newState, events)`. State is immutable. Illegal actions return a reason code and leave state unchanged.
4. **Money is `int` rupees.** Never `double`. Display with Indian grouping (₹15,00,000).
5. **Dice come only from the server**, using a CSPRNG with commit–reveal (hash before roll, key revealed after).
6. **Total money is conserved.** Players + bank + Free Parking pot always equals the starting total. Simulation tests assert this.
7. **No text input for chat.** Communication is push-to-talk voice and fixed emotes only.
8. **Voice clips are never written to disk** on any server; drop after delivery.
9. **Every message carries the protocol version.** Unknown or malformed messages produce a typed error, never a crash.
10. **Board and cards come from JSON** (`board.json`, `cards.json`). No hard-coded tile data in code.

## Key game constants (defaults, configurable)

- Starting cash: ₹15,00,000 per player. Salary for passing Start: ₹2,00,000.
- Jail fine: ₹50,000. Unmortgage interest: 10%. Bank holds 32 houses and 12 hotels.
- Card decks: **Vaaippu** (Chance) and **Undiyal** (Community Chest), 16 cards each.
- Tokens: auto-rickshaw, Ambassador car, elephant, cricket bat, kite, tea glass.
- Ports: WebSocket 47800, UDP discovery 47801.

## How to work

- Implement **one story at a time** from `docs/backlog.md`, in wave order. Stories in the same wave may run in parallel unless "Depends on" says otherwise.
- **Write tests first**, then code; run until green.
- Stay inside the story's scope. List follow-ups instead of doing them.
- Definition of done for every story:
  - All acceptance criteria pass.
  - `dart analyze` clean, `dart format` applied.
  - New code has unit tests; all existing tests pass in CI.
  - Public APIs have short doc comments.
- When done, summarise what changed and how to verify it.

## Commands (once VY-1 is done)

```
dart pub get                 # in each package, or via workspace
dart analyze
dart format .
dart test                    # core, protocol, server
flutter test                 # app
flutter run -d chrome        # web client
dart compile exe server_bin/main.dart -o build/vyapari_server
```
