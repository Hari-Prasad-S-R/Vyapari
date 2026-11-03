# Vyapari — Development Backlog

Last updated: 2026-11-03 · Read `CLAUDE.md`, `requirements.md` and `design.md` first.

40 stories in 8 waves. Finish every story in a wave before starting the next. Stories inside a wave can run in parallel unless **Depends on** says otherwise. Waves 0–6 deliver the internal release; Wave 7 waits for real demand.

**Sizes:** S = under a day · M = 1–2 days · L = 3–5 days · XL = over a week.

## How to give a story to Claude

```
You are building Vyapari, a Flutter + Dart board game.
Read CLAUDE.md, docs/requirements.md and docs/design.md first.

Implement story <ID> from docs/backlog.md.

Rules:
- Keep packages/core free of Flutter and network code.
- Write the tests first, then the code, and run them until green.
- Do not change code outside this story's scope; list follow-ups instead.
- All acceptance criteria must pass.
- When done, summarise what changed and how to verify it.
```

## Definition of done (every story)

- All acceptance criteria pass.
- `dart analyze` clean; `dart format` applied.
- New code has unit tests; all existing tests pass in CI.
- Public classes and functions have short doc comments.
- Merged to `main` via a reviewed pull request.

## Tracker

| ID | Story | Wave | Depends on | Size | Status |
| --- | --- | --- | --- | --- | --- |
| VY-1 | Monorepo and CI setup | 0 | — | S | Done (CI not yet run on GitHub) |
| VY-2 | Core data models | 0 | VY-1 | M | Done |
| VY-3 | Board and card data | 0 | VY-2 | M | Done |
| VY-4 | Fair dice service | 1 | VY-2 | S | Done |
| VY-5 | Turn engine | 1 | VY-3, VY-4 | L | Done |
| VY-6 | Buying and auctions | 1 | VY-5 | M | Done |
| VY-7 | Rent calculation | 1 | VY-5 | M | Done |
| VY-8 | Vaaippu and Undiyal cards | 1 | VY-5 | M | Done |
| VY-9 | Jail | 1 | VY-5 | S | Done |
| VY-10 | Building and mortgages | 1 | VY-7 | M | Done |
| VY-11 | Player-to-player trades | 1 | VY-10 | M | Done |
| VY-12 | Bankruptcy and game end | 1 | VY-10 | M | Done |
| VY-13 | House-rule toggles | 1 | VY-6, VY-9 | S | Done |
| VY-14 | Simulation harness and bots | 1 | VY-6 … VY-13 | M | Done |
| VY-15 | Protocol package | 2 | VY-2 | M | Done |
| VY-16 | Game server: rooms, lobby, play | 2 | VY-14, VY-15 | L | Done |
| VY-17 | Sessions and reconnect | 2 | VY-16 | M | Done |
| VY-18 | Bot seats and turn timer | 2 | VY-16 | M | Done |
| VY-19 | Save and resume | 2 | VY-16 | S | Done |
| VY-20 | Online server and Docker | 2 | VY-17, VY-19 | S | Built; Docker image not yet built |
| VY-21 | App shell and responsive layout | 3 | VY-15 | M | Done |
| VY-22 | Board rendering | 3 | VY-21, VY-3 | L | Done |
| VY-23 | Home and join screens | 3 | VY-21 | S | Done |
| VY-24 | Lobby screen | 3 | VY-23 | M | Done |
| VY-25 | Game screen and turn actions | 3 | VY-22, VY-24 | L | Done |
| VY-26 | Trade screen | 3 | VY-25 | M | Done |
| VY-27 | Activity log, emotes, results | 3 | VY-25 | S | Done |
| VY-28 | Host a game from the phone | 4 | VY-27 | L | Built; needs device test |
| VY-29 | Discover nearby games | 4 | VY-28 | M | Built (UDP + mDNS hybrid); needs device test |
| VY-30 | Hotspot setup guidance | 4 | VY-28 | S | Done |
| VY-31 | Record and send a clip | 5 | VY-28 | M | Built; needs device test |
| VY-32 | Voice relay on the server | 5 | VY-15, VY-16 | M | Done |
| VY-33 | Auto-play, mute and replay | 5 | VY-31, VY-32 | M | Built; playback needs device test |
| VY-34 | Security and fair-dice proof | 6 | VY-30, VY-33 | M | Done |
| VY-35 | Performance and device testing | 6 | VY-34 | M | Load test done; device/battery tests pending |
| VY-36 | Internal release builds | 6 | VY-35 | S | Workflows, guide, Gradle signing done; keystore needed |
| VY-37 | Split gateways and game nodes | 7 | VY-36 | XL | To do |
| VY-38 | NATS voice bus | 7 | VY-37 | L | To do |
| VY-39 | Accounts, stats and events | 7 | VY-37 | L | To do |
| VY-40 | Kubernetes, observability, load test | 7 | VY-38, VY-39 | XL | To do |

---

## Wave 0 — Foundation

**Goal:** a building, tested repo with the game's data shapes. **Exit gate:** CI green and the board loads from JSON.

### VY-1 · Monorepo and CI setup
- **Story:** As a developer, I want one repo with the four packages and CI so that every change is built and tested automatically.
- **Depends on:** — · **Size:** S

**Build**
- Dart workspace: `packages/core`, `packages/protocol`, `packages/server`, `packages/app` (Flutter), `server_bin/`.
- Shared `analysis_options.yaml` with strict lints.
- GitHub Actions: analyze, format check, test for all packages; build Android APK and web on `main`.
- README with setup and run commands.

**Test**
- One placeholder test per package runs in CI.

**Acceptance criteria**
- [ ] Given a fresh clone, when I run the README commands, then all packages build and tests pass.
- [ ] Given a pull request, when CI runs, then analyze, format and tests run for every package.
- [ ] `packages/core` has no Flutter or `dart:io` imports (enforced by a CI step).

### VY-2 · Core data models
- **Story:** As a developer, I want immutable models for the whole game so that state can be copied, saved and sent safely.
- **Depends on:** VY-1 · **Size:** M

**Build**
- `GameState`, `Player`, `Tile`, `Ownership`, `Card`, `Trade`, `Auction`, `HouseRules`, `Session` as in `design.md` §4.
- Immutable classes with `copyWith`, value equality, `toJson` / `fromJson`.
- Money as `int` rupees only.

**Test**
- JSON round-trip for every model; equality and `copyWith` tests.

**Acceptance criteria**
- [ ] Given any model, when encoded to JSON and decoded, then it equals the original.
- [ ] Given a `GameState`, when a field changes via `copyWith`, then the original is unchanged.
- [ ] No `double` is used for money anywhere.

### VY-3 · Board and card data
- **Story:** As a designer, I want the board and cards in JSON so that I can change cities, prices and cards without code.
- **Depends on:** VY-2 · **Size:** M

**Build**
- `assets/boards/india/board.json`: 40 tiles — 22 cities in 8 groups (see `requirements.md` §4), 4 transport, 2 utilities, 2 taxes, 4 corners, card tiles; prices and rent tables.
- `cards.json`: 16 Vaaippu + 16 Undiyal cards, original text, typed effects.
- Loader with validation (40 tiles, unique indexes, complete groups, valid effects).
- Config: starting cash ₹15,00,000, salary ₹2,00,000, jail fine ₹50,000.
- ₹ formatter with Indian grouping.

**Test**
- Loader accepts real files; rejects broken ones (39 tiles, duplicate index, unknown effect) with clear errors.

**Acceptance criteria**
- [ ] Given the India files, when loaded, then 40 tiles and 32 cards are available.
- [ ] Given a file with a missing tile, when loaded, then a validation error names the problem.
- [ ] Amounts format as Indian grouping, e.g. ₹15,00,000.

---

## Wave 1 — Rules engine (pure Dart)

**Goal:** a complete game that bots can play end to end with no UI or network. **Exit gate:** 10,000 simulated games finish with no crash and money always balanced. VY-4 and VY-5 first; VY-6 to VY-9 then in parallel; VY-10 to VY-14 follow their dependencies.

### VY-4 · Fair dice service
- **Story:** As a player, I want dice nobody can fake so that I trust every roll.
- **Depends on:** VY-2 · **Size:** S

**Build**
- Two-dice roll from a cryptographically secure source.
- Commit–reveal: before a roll publish SHA-256(key + roll number); after it reveal the key; key rotates per game.
- Injectable seeded source for tests.

**Test**
- 1,000,000 rolls: each face 16.7% ± 0.2%.
- Verify accepts real reveals, rejects changed results.

**Acceptance criteria**
- [ ] Given a commit and its reveal, when verify runs, then it confirms the roll.
- [ ] Given a tampered roll, when verified, then verify fails.
- [ ] Given a fixed test seed, when rolling, then results repeat.

### VY-5 · Turn engine: roll, move, salary, doubles
- **Story:** As a player, I want turns to flow correctly so that the game plays like the real board game.
- **Depends on:** VY-3, VY-4 · **Size:** L

**Build**
- Reducer `apply(action, state) -> (state, events)`; illegal actions return a reason code and unchanged state.
- Turn phases per `design.md` §6.
- Move with wrap past tile 39; salary on passing Start; doubles roll again; third double → jail without moving.
- `version` increments on every accepted action.

**Test**
- Table tests for every phase transition.
- Illegal actions: roll out of turn, roll twice, end turn before rolling.

**Acceptance criteria**
- [ ] Given a player on tile 38, when they roll 5, then they land on tile 3 and receive ₹2,00,000.
- [ ] Given a player rolls doubles, when the move resolves, then they roll again.
- [ ] Given a third double in a row, when rolled, then the player goes to jail without moving.
- [ ] Given it is not my turn, when I send `roll`, then it is rejected with `not_your_turn` and state is unchanged.

### VY-6 · Buying and auctions
- **Story:** As a player, I want to buy an unowned city or auction it so that properties change hands fairly.
- **Depends on:** VY-5 · **Size:** M

**Build**
- Buy at list price if cash allows; decline starts an auction (unless off).
- Auction: all solvent players bid; 10 s per bid round; highest bid wins; min step ₹10,000.

**Test**
- Buy with enough and not enough cash; auctions with 0, 1, many bidders.

**Acceptance criteria**
- [ ] Given I land on unowned Chennai with enough cash, when I buy, then I own it and cash drops by its price.
- [ ] Given I decline with auctions on, when bidding ends, then the highest bidder pays and owns it.
- [ ] Given nobody bids, when the auction ends, then the city stays with the bank.

### VY-7 · Rent calculation
- **Story:** As an owner, I want rent charged automatically so that nobody argues about amounts.
- **Depends on:** VY-5 · **Size:** M

**Build**
- City: base, double for full set without buildings, 1–4 houses, hotel.
- Transport by count owned (1–4). Utilities: dice total × 4 (one) or × 10 (both), scaled to board unit.
- No rent on mortgaged tiles or to oneself. Respect `noRentInJail` toggle.

**Test**
- Table test covering every rent case on the India board.

**Acceptance criteria**
- [ ] Given an owner of the full Chennai group with no houses, when someone lands there, then double base rent is paid.
- [ ] Given a mortgaged tile, when someone lands there, then no rent is paid.
- [ ] Given both utilities owned and a roll of 8, when landing on one, then rent = 8 × 10 × board unit.

### VY-8 · Vaaippu and Undiyal cards
- **Story:** As a player, I want cards to apply automatically so that play keeps moving.
- **Depends on:** VY-5 · **Size:** M

**Build**
- Shuffle each deck per game from the game seed; draw from top, return to bottom.
- Effects: `collect`, `pay`, `payEachPlayer`, `collectFromEachPlayer`, `moveTo`, `moveBack`, `goToJail`, `getOutOfJail`, `repairs`.
- A held get-out card leaves the deck until used.

**Test**
- One test per effect type; deck order repeatable with fixed seed.

**Acceptance criteria**
- [ ] Given a "move to Start" card, when drawn, then the player moves to Start and collects salary.
- [ ] Given a get-out card is held, when the deck cycles, then that card is not drawn until used.
- [ ] Every card in `cards.json` is covered by a passing test.

### VY-9 · Jail
- **Story:** As a jailed player, I want clear ways out so that jail is fair.
- **Depends on:** VY-5 · **Size:** S

**Build**
- Pay ₹50,000, use a card, or roll doubles (max 3 tries; after the third miss, pay and move).
- "Just Visiting" does nothing.

**Test**
- All exit paths and forced pay on the third try.

**Acceptance criteria**
- [ ] Given I roll doubles in jail, when it resolves, then I leave and move but do not roll again.
- [ ] Given my third failed try, when it resolves, then I pay the fine and move by that roll.

### VY-10 · Building and mortgages
- **Story:** As an owner, I want to build, sell and mortgage so that I can grow or raise cash.
- **Depends on:** VY-7 · **Size:** M

**Build**
- Build only on full, unmortgaged sets; even-build rule; bank limit 32 houses, 12 hotels.
- Sell buildings at half cost; mortgage at half price (only with no buildings in the group); unmortgage at value + 10%.

**Test**
- Even-build violations, house shortage, mortgaging with buildings present.

**Acceptance criteria**
- [ ] Given I own 2 of 3 cities in a group, when I build, then it fails with `incomplete_set`.
- [ ] Given the bank has 0 houses, when I build, then it fails with `no_houses_left`.
- [ ] Given a mortgaged city, when I unmortgage, then I pay mortgage value + 10%.

### VY-11 · Player-to-player trades
- **Story:** As a player, I want to trade cities, cash and cards with others so that I can complete sets.
- **Depends on:** VY-10 · **Size:** M

**Build**
- Propose, accept, reject, counter; proposals any time, applied only between phases.
- Re-validate ownership, cash and no-buildings-on-group at accept.
- Hooks for optional rent-immunity and loan toggles (off by default, not implemented yet).

**Test**
- Valid trade; trade invalidated by a change before accept; trade with buildings on the group.

**Acceptance criteria**
- [ ] Given a valid offer, when accepted, then both sides swap exactly what was offered.
- [ ] Given the proposer spent the cash before acceptance, when accepted, then it fails with `trade_invalid` and nothing moves.
- [ ] Bankrupt or disconnected players cannot propose or receive trades.

### VY-12 · Bankruptcy and game end
- **Story:** As a player, I want debts and bankruptcy handled correctly so that the game ends cleanly.
- **Depends on:** VY-10 · **Size:** M

**Build**
- A player owing more than their cash must raise cash (sell, mortgage, trade) before ending the turn.
- If still short: bankrupt; assets go to the creditor, or to the bank (auctioned) if owed to the bank.
- Game ends with one player left, or at time/turn limit (highest net worth wins).

**Test**
- Bankrupt to player, to bank, time-limit end with net-worth tie-break.

**Acceptance criteria**
- [ ] Given a player is bankrupted by another, when it resolves, then all their cities and cash go to that player.
- [ ] Given one player remains, when the last bankruptcy resolves, then the game ends with them as winner.

### VY-13 · House-rule toggles
- **Story:** As a host, I want to switch popular house rules on or off so that we play our family's way.
- **Depends on:** VY-6, VY-9 · **Size:** S

**Build**
- Free Parking pot, double salary on landing on Start, no auctions, no rent while in jail, quick game (2 random cities each, 60-min limit).

**Test**
- Each toggle on/off changes only its own behaviour.

**Acceptance criteria**
- [ ] Given Free Parking pot on, when tax is paid, then it goes to the pot and the next player landing on Free Parking takes it.
- [ ] Given all toggles off, when a game is played, then classic rules apply.

### VY-14 · Simulation harness and basic bots
- **Story:** As a developer, I want thousands of bot games run automatically so that rule bugs show up early.
- **Depends on:** VY-6 to VY-13 · **Size:** M

**Build**
- Easy bot (random legal moves); Medium bot (buys if cash after > ₹3,00,000, builds on full sets).
- Simulator: N games, 2–8 bots, random house rules; reports crashes, stuck games, money leaks.

**Test**
- Harness tests; CI runs 1,000 games per push and 10,000 nightly.

**Acceptance criteria**
- [ ] Given 10,000 simulated games, when run, then none crash or exceed 500 turns.
- [ ] After every action, players + bank + Free Parking pot equals the starting total.

---

## Wave 2 — Protocol and server

**Goal:** command-line test clients play a full game against one server. **Exit gate:** 6 clients finish a game over WebSocket, including one disconnect and rejoin. VY-15 first.

### VY-15 · Protocol package
- **Story:** As a developer, I want one shared definition of every message so that app and server always agree.
- **Depends on:** VY-2 · **Size:** M

**Build**
- Envelope `{v, type, id, room, data}`; a class per message type in `design.md` §5; error reason codes enum.
- Binary voice frame: header length, JSON header, audio bytes.
- Protocol version constant; unknown types decode to a typed error.

**Test**
- Round trip for every message and the voice frame; malformed JSON and unknown type tests.

**Acceptance criteria**
- [ ] Given any message, when encoded and decoded, then it equals the original.
- [ ] Given malformed input, when decoded, then a typed error returns and nothing throws.

### VY-16 · Game server: rooms, lobby and play
- **Story:** As a host, I want a server that runs rooms and the full game so that players on other devices can join and play.
- **Depends on:** VY-14, VY-15 · **Size:** L

**Build**
- `shelf` + `shelf_web_socket`; create room with random 4-digit code (6 characters online).
- `hello` / `welcome`; lobby actions with host-only checks.
- Route turn actions through the rules engine; broadcast `patch` + events to all; `error` only to the sender.
- Opening roll sets turn order; 2–8 players.

**Test**
- Integration: 6 in-process clients play a seeded game to the end.
- Host-only actions rejected for non-hosts.

**Acceptance criteria**
- [ ] Given 3 clients in a lobby, when the host starts, then all receive the same initial state and turn order.
- [ ] Given a player buys a city, when applied, then every client gets the patch within 150 ms on localhost.
- [ ] Given a non-host sends `kick`, then it is rejected with `host_only`.

### VY-17 · Sessions, heartbeat and reconnect
- **Story:** As a player with patchy Wi-Fi, I want my seat back after a drop so that I don't lose the game.
- **Depends on:** VY-16 · **Size:** M

**Build**
- Session token in `welcome`; ping every 10 s; disconnected after 20 s silence.
- Rejoin with token + last `version` within 3 minutes → `patch` or full `state`.
- While disconnected: bot plays the turn or turn auto-skips (host setting).

**Test**
- Drop mid-turn, rejoin after 30 s, state matches others; rejoin after 3 min refused, seat goes to a bot.

**Acceptance criteria**
- [ ] Given I lose connection for 1 minute, when I reconnect, then I am back in my seat with current state.
- [ ] Given I am disconnected on my turn with bot cover on, then a bot plays that turn.

### VY-18 · Bot seats, hard bot and turn timer
- **Story:** As a host, I want bots in empty seats and turns that keep moving so that games never stall.
- **Depends on:** VY-16 · **Size:** M

**Build**
- Host adds Easy/Medium/Hard bots in the lobby.
- Hard bot: values set completion, proposes and judges trades, keeps a cash reserve.
- Turn timer (default 60 s); on timeout the server ends the turn safely.

**Test**
- 1,000 games: Hard beats Easy in ≥ 70%. Timer expiry in each phase leaves valid state.

**Acceptance criteria**
- [ ] Given 2 humans, when the host adds 2 bots, then the game starts with 4 players.
- [ ] Given the timer runs out, when it fires, then the turn ends and play passes on.

### VY-19 · Save and resume
- **Story:** As a host, I want to save and resume games so that long games can span days.
- **Depends on:** VY-16 · **Size:** S

**Build**
- Local: JSON save per room after each turn; resume list.
- Online: SQLite behind a storage interface.

**Test**
- Save, restart, resume: identical state. Corrupt save reported, not crashed on.

**Acceptance criteria**
- [ ] Given a saved game, when the host resumes and players rejoin, then play continues from the same turn.

### VY-20 · Online server build and Docker
- **Story:** As the owner, I want the server on my home lab so that remote friends can play.
- **Depends on:** VY-17, VY-19 · **Size:** S

**Build**
- `server_bin` via `dart compile exe`; Docker image < 50 MB.
- `docker-compose.yml` with Caddy (TLS, `wss://`) and a SQLite volume.
- `/health` endpoint; logs to stdout.

**Test**
- Container starts; health passes; a test client completes a game over `wss://`.

**Acceptance criteria**
- [ ] Given `docker compose up`, when a client connects over `wss://`, then it can create and play a room.
- [ ] Given the container restarts, when players rejoin, then saved games resume.

---

## Wave 3 — App screens

**Goal:** a playable Flutter app on Android, iOS and web that joins the Wave 2 server by IP or room code. **Exit gate:** 4 people on 4 screen sizes finish a game. VY-21 and VY-22 first.

### VY-21 · App shell, theme and responsive layout
- **Story:** As a player, I want the app to look right on any screen so that I can play on phone, tablet, laptop or TV.
- **Depends on:** VY-15 · **Size:** M

**Build**
- Routing (Home, Join, Lobby, Game, Results), Riverpod, light and dark theme.
- Breakpoints < 600, 600–1023, ≥ 1024 px (`design.md` §8).
- Connection service: WebSocket client, sends intents, applies `state`/`patch`, ignores older versions.

**Test**
- Widget tests at 360, 800, 1440 px; connection service with a fake server.

**Acceptance criteria**
- [ ] Given a 360 px phone, when any screen opens, then nothing overflows and buttons are ≥ 44 px.
- [ ] Given a stale patch, when applied, then it is ignored.

### VY-22 · Board rendering
- **Story:** As a player, I want a clear board that scales to my screen so that I always see where everyone is.
- **Depends on:** VY-21, VY-3 · **Size:** L

**Build**
- `CustomPainter` board from `board.json`: tiles, colour bands, prices, owner markers, houses/hotels, mortgaged state.
- Tokens with tile-by-tile move animation.
- Tap a tile for details (price, rent table, owner).

**Test**
- Golden tests at 3 sizes; animation test passing Start.

**Acceptance criteria**
- [ ] Given any screen from 360 px to 4K, when drawn, then the board is square, fully visible, tile text ≥ 10 px.
- [ ] Given a 7-tile move, when animated, then it steps through each tile in under 2 s.

### VY-23 · Home and join screens
- **Story:** As a player, I want to pick my name and token and join quickly so that setup takes seconds.
- **Depends on:** VY-21 · **Size:** S

**Build**
- Home: name, token picker, Host / Join nearby / Join online / Play vs bots, app version.
- Join: manual IP + port, online room code, saved servers (discovery in Wave 4).
- Errors: wrong code, room full, version mismatch ("Please update the app").

**Test**
- Widget test per error message.

**Acceptance criteria**
- [ ] Given a valid room code, when I tap Join, then I reach the lobby in < 2 s on the local network.
- [ ] Given a full room, when I join, then I see "Room is full" and stay on the join screen.

### VY-24 · Lobby screen
- **Story:** As a host, I want to see who joined and set rules so that we start when ready.
- **Depends on:** VY-23 · **Size:** M

**Build**
- Large room code + QR; player list with tokens and ready ticks.
- Host-only: house rules, starting cash, turn timer, bots, kick, Start. Others see settings read-only.

**Test**
- Host vs non-host widget tests; Start disabled until 2+ ready.

**Acceptance criteria**
- [ ] Given a player joins, then every device shows them within 1 s.
- [ ] Given I am not the host, then I cannot change settings.

### VY-25 · Game screen and turn actions
- **Story:** As a player, I want only legal moves shown so that turns are quick and clear.
- **Depends on:** VY-22, VY-24 · **Size:** L

**Build**
- Phase-driven action bar: Roll, Buy, Decline/Bid, Pay fine, Use card, End turn.
- Dice animation; rent/card/tax pop-ups with amounts; cash change animation.
- Players panel; my cities sheet with Build, Sell, Mortgage, Unmortgage.

**Test**
- Widget test per phase for legal buttons; integration game vs bots.

**Acceptance criteria**
- [ ] Given it is not my turn, then turn buttons are hidden.
- [ ] Given rent is charged, then both players see the amount and updated cash.
- [ ] Given I own a full set, then Build is enabled only where even-build allows.

### VY-26 · Trade screen
- **Story:** As a player, I want a simple trade builder so that deals are clear.
- **Depends on:** VY-25 · **Size:** M

**Build**
- Pick a player; "I give" / "I get" columns with cities, cash slider, cards.
- Incoming offer sheet: Accept, Reject, Counter; Accept disabled 3 s.
- "Lopsided" warning when values differ by more than 5×.

**Test**
- Widget tests: build, counter, review delay.

**Acceptance criteria**
- [ ] Given an incoming offer, then Accept is disabled for 3 s.
- [ ] Given the offer changes during review, then the 3 s timer restarts.

### VY-27 · Activity log, emotes and results
- **Story:** As a player, I want to see what happened, react and see the ranking so that the game feels social.
- **Depends on:** VY-25 · **Size:** S

**Build**
- Activity log of every roll, purchase, rent, card, trade, bankruptcy.
- Emote bar (Aiyo!, Semma!, thumbs up) shown over sender's token for 2 s. No text input anywhere.
- Results: winner, net-worth ranking, Rematch.

**Test**
- Log matches server events in an integration test.

**Acceptance criteria**
- [ ] Given any event, then it appears in every player's log in the same order.
- [ ] Given the game ends, when Rematch is tapped, then a new lobby opens with the same players.

---

## Wave 4 — Local hosting over hotspot and Wi-Fi

**Goal:** Mini Militia experience — one phone hosts, others find it, no internet. **Exit gate:** 6 phones on one Android hotspot, mobile data off, finish a 90-minute game.

### VY-28 · Host a game from the phone
- **Story:** As a host, I want to start a game from my phone so that friends join with no internet or server.
- **Depends on:** VY-27 · **Size:** L

**Build**
- "Host" starts the `server` package in-app on port 47800; host joins as a normal player.
- Android: foreground service + notification keeps server alive with screen off.
- iOS: hosts while app open; warn that leaving pauses the game.
- Web: Host hidden (join-only).

**Test**
- Integration: app hosts, 3 emulator clients play. Android screen off 10 min: game continues.

**Acceptance criteria**
- [ ] Given I tap Host, then the lobby shows my IP, room code and QR within 2 s.
- [ ] Given my Android screen turns off, then the game keeps running.
- [ ] Given the host leaves, then the game pauses and offers save.

### VY-29 · Discover nearby games
- **Story:** As a player, I want nearby games listed automatically so that I join with one tap.
- **Depends on:** VY-28 · **Size:** M

**Build**
- Host broadcasts name, code, player count, version over UDP 47801 every 2 s, plus mDNS.
- "Join nearby" list drops games not heard for 6 s.
- QR join via `vyapari://join?ip=…&port=…&code=…`.

**Test**
- Two hosts both appear; a stopped host disappears within 6 s.

**Acceptance criteria**
- [ ] Given a host on the same hotspot, then it appears in Join nearby within 3 s.
- [ ] Given I scan the QR, then I land in the lobby without typing.

### VY-30 · Hotspot setup guidance
- **Story:** As a host without Wi-Fi, I want clear hotspot steps so that setup isn't confusing.
- **Depends on:** VY-28 · **Size:** S

**Build**
- Detect no network; show a short guide with a button opening hotspot settings.
- Optional room password.

**Test**
- Guide widget test; password accept/reject.

**Acceptance criteria**
- [ ] Given no network, when I tap Host, then I see the hotspot guide, not an error.
- [ ] Given a wrong password, then the player cannot join.

---

## Wave 5 — Push-to-talk voice

**Goal:** walkie-talkie voice to everyone, one player, or 2–3 players, offline. **Exit gate:** on a 6-phone hotspot, clips reach only chosen people and play within 1 s of release.

### VY-31 · Record and send a clip
- **Story:** As a player, I want to hold, speak and choose who hears so that we talk like walkie-talkies.
- **Depends on:** VY-28 · **Size:** M

**Build**
- Floating talk button: long-press records, release sends; 15 s max with countdown ring.
- Recipient picker: Broadcast (default), one player, or 2–3 players; remembers last group.
- Opus on Android/web, AAC on iOS; send as binary voice frame.
- Mic permission prompt with clear reason.

**Test**
- Picker widget test; recording auto-stops at 15 s.

**Acceptance criteria**
- [ ] Given I hold 20 s, then recording stops at 15 s and sends.
- [ ] Given I pick 2 players, then the frame's recipients are exactly those 2.
- [ ] There is no text input anywhere in the app.

### VY-32 · Voice relay on the server
- **Story:** As a player, I want private clips to reach only chosen people so that private talk stays private.
- **Depends on:** VY-15, VY-16 · **Size:** M

**Build**
- Route to all room players or listed ids; reject unknown ids.
- Limits: 1 clip / 3 s / player; 60 KB max; host can mute a player room-wide.
- Memory only; drop after delivery.

**Test**
- Private clip to 2 of 5: other 3 get nothing. Rate and size limit rejections.

**Acceptance criteria**
- [ ] Given a clip to B and C, then only B and C receive it.
- [ ] Given a muted player sends, then nobody receives it.
- [ ] No clip is ever written to disk on the server.

### VY-33 · Auto-play, mute and replay
- **Story:** As a listener, I want clips to auto-play in order so that I never miss what was said.
- **Depends on:** VY-31, VY-32 · **Size:** M

**Build**
- Queue: auto-play on arrival, never overlapping; speaking banner (name, token, "private").
- Per-player mute, mute-all, volume.
- Replay last 5 clips.

**Test**
- Three simultaneous clips play in order without overlap.

**Acceptance criteria**
- [ ] Given two clips within 1 s, then the second starts after the first ends.
- [ ] Given I muted a player, then their broadcasts don't play for me.
- [ ] Given I return from background, then I can replay missed clips.

---

## Wave 6 — Hardening and internal release

**Goal:** a fair, stable build installed by family and friends. **Exit gate:** all NFRs met; builds installed on Android, iOS and web.

### VY-34 · Security and fair-dice proof
- **Story:** As a player, I want to trust the game and rooms so that nobody cheats or barges in.
- **Depends on:** VY-30, VY-33 · **Size:** M

**Build**
- "Verify dice" view in the log (commit, reveal, pass/fail).
- 5 wrong codes/passwords → device blocked 1 minute.
- Reject any non-intent message; protocol fuzzing.

**Test**
- Fuzz with 100,000 random messages: no crash, no state change. Rate-limit test.

**Acceptance criteria**
- [ ] Given any past roll, when I open Verify, then it shows pass.
- [ ] Given 5 wrong codes from a device, then a 6th within 1 min is refused.
- [ ] Given malformed messages, then the server stays up and state is unchanged.

### VY-35 · Performance and device testing
- **Story:** As a player on a cheap phone, I want smooth play and low battery use.
- **Depends on:** VY-34 · **Size:** M

**Build**
- Profile and fix hot spots on a 3 GB RAM Android host.
- Online load test: 1,000 bot rooms on one server.

**Test**
- 90-minute hotspot game with 6 phones; measure battery, fps, latency.

**Acceptance criteria**
- [ ] Board animations hold 30 fps on the low-end phone.
- [ ] Local latency < 150 ms; online < 500 ms.
- [ ] Host uses < 25% battery in 90 minutes.
- [ ] One online server handles 1,000 bot rooms with no errors.

### VY-36 · Internal release builds
- **Story:** As the owner, I want easy installs for my group so that we can play.
- **Depends on:** VY-35 · **Size:** S

**Build**
- Signed Android APK; iOS via TestFlight; web client on home lab over HTTPS.
- CI builds all three on a version tag; version on Home.
- In-app how-to-play and how-to-host guide.

**Test**
- Fresh install on each platform joins a game.

**Acceptance criteria**
- [ ] Given a version tag, then CI produces APK, iOS and web builds.
- [ ] Given a new player, then they can install and join a game in under 5 minutes.

---

## Wave 7 — Scale-out (after internal release)

**Goal:** grow online mode toward the 100-million-user design (`design.md` §10) without changing game code. Start only when real usage needs it; split each story further at that time.

### VY-37 · Split gateways and game nodes
- **Depends on:** VY-36 · **Size:** XL
- **Build:** stateless WebSocket gateways; room-owning game nodes; Redis room directory and per-turn snapshots; room recovery on node failure.
- **Test:** kill a node mid-game; chaos test with random restarts.
- **Acceptance criteria**
  - [ ] Given a game node dies, then its rooms resume from the last turn within 10 s after reconnect.
  - [ ] Adding a gateway or game node needs no code change or downtime.

### VY-38 · NATS voice bus
- **Depends on:** VY-37 · **Size:** L
- **Build:** gateways relay voice over NATS room channels; game nodes never see audio.
- **Test:** room members on different gateways exchange private and broadcast clips.
- **Acceptance criteria**
  - [ ] Given members on 3 gateways, when one broadcasts, then all hear it within 1 s.

### VY-39 · Accounts, stats and events
- **Depends on:** VY-37 · **Size:** L
- **Build:** sign-in, profiles, friends, stats in PostgreSQL sharded by user id; finished-game events to Kafka.
- **Test:** shard routing; account migration between shards.
- **Acceptance criteria**
  - [ ] Given 10 million test accounts, then sign-in completes in < 300 ms.

### VY-40 · Kubernetes, observability and load test
- **Depends on:** VY-38, VY-39 · **Size:** XL
- **Build:** Kubernetes in Mumbai and Hyderabad with autoscaling; CDN; Prometheus, Grafana, OpenTelemetry; node draining at turn boundaries.
- **Test:** ramp headless bots to 1.5 million players.
- **Acceptance criteria**
  - [ ] Given 1.5 million simulated players for 1 hour, then turn latency < 500 ms and reconnect rate < 1%.
  - [ ] Given a deploy, then no game is interrupted.
