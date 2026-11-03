# Vyapari

Indian-themed property trading board game for 2–8 players — Android, iOS and
web. One phone hosts over Wi-Fi or its hotspot (no internet), or everyone joins
an online server by room code. Push-to-talk voice only; no typed chat.

Read [CLAUDE.md](CLAUDE.md) first, then [docs/requirements.md](docs/requirements.md),
[docs/design.md](docs/design.md) and [docs/backlog.md](docs/backlog.md).

## Layout

| Path | What |
| --- | --- |
| `packages/core` | Pure Dart: models, rules engine (`apply(action, state)`), fair dice, bots, simulator |
| `packages/protocol` | Envelope, message classes, JSON codecs, binary voice frame |
| `packages/server` | Rooms, sessions/reconnect, WebSocket hub, voice relay, saves, LAN discovery |
| `packages/app` | Flutter app (Riverpod): home, join, lobby, game, trade, results, voice |
| `server_bin` | Online server entry point (`dart compile exe`, Docker) |
| `assets/boards/india` | `board.json` + `cards.json` — the only source of tile and card data |

## Setup

Requires Flutter (stable, Dart ≥ 3.6). One `pub get` at the root resolves the
whole workspace.

```bash
flutter pub get
```

## Test

```bash
tool/check_core_pure.sh
(cd packages/core && dart test)                       # rules + 1,000 simulated games
(cd packages/core && VYAPARI_SIM_GAMES=10000 dart test test/simulation_test.dart)
(cd packages/protocol && dart test)
(cd packages/server && dart test)                     # 6 WebSocket clients play a full game
(cd packages/server && VYAPARI_LOAD_ROOMS=1000 dart test -t load --run-skipped)
(cd packages/app && flutter test --exclude-tags golden)
```

Analyze and format:

```bash
dart analyze packages/core packages/protocol packages/server server_bin
(cd packages/app && flutter analyze)
dart format packages server_bin
```

## Run

Online server (also serves the web client if you pass `--web`):

```bash
(cd packages/app && flutter build web --release)
dart run server_bin/bin/main.dart --port=47800 --web=packages/app/build/web
```

Open <http://localhost:47800>, enter a nickname, **Join online → Create a new
room**, add bots and start. Health check: <http://localhost:47800/health>.

App on a device or emulator (Android/iOS can host; web is join-only):

```bash
cd packages/app && flutter run
```

Native server binary:

```bash
dart compile exe server_bin/bin/main.dart -o build/vyapari_server
```

### Docker (home lab)

```bash
VYAPARI_DOMAIN=vyapari.example.in docker compose up -d --build
```

Caddy terminates TLS (`wss://`), proxies `/ws`, `/health` and `/rooms` to the
server, and serves `packages/app/build/web`. Saves live in the `vyapari-data`
volume (SQLite); unfinished rooms resume after a restart and players rejoin
with their session token.

## Editing the board

Change `assets/boards/india/*.json`, then copy them into the app bundle:

```bash
tool/sync_assets.sh
```

The loader validates the files (40 tiles, unique indexes, complete groups,
16 cards per deck, known effects) and names every problem it finds.

## Ports

WebSocket/HTTP 47800 · UDP discovery 47801.
