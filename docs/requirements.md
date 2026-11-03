# Vyapari — Requirements

Status: approved for internal build · Owner: Hari · Last updated: 2026-11-03

## 1. Overview and goals

Vyapari is an Indian-themed property trading board game for 2–8 players. It works fully offline over a phone hotspot or LAN, and optionally over the internet through a hosted server — the same two-mode model Mini Militia used.

- **G1:** Any player can host a game from their phone; others join over the same Wi-Fi or hotspot with no internet.
- **G2:** The same app can join a dedicated online server for remote friends.
- **G3:** Indian look and feel — Indian cities, ₹ currency, familiar house rules as toggles.
- **G4:** Fair play — the host or server is the single source of truth for dice, money and ownership.

**Naming:** "Monopoly" is a Hasbro trademark. The product is named **Vyapari** and must use original board art and original card text. Do not use the names "Chance", "Community Chest", "Go to Jail" or "Free Parking" in the shipped UI if avoidable; internal code may use generic names.

## 2. Decisions (resolved)

| Topic | Decision |
| --- | --- |
| Game name | Vyapari |
| Tokens | auto-rickshaw, Ambassador car, elephant, cricket bat, kite, tea glass |
| Platforms | Android, iOS and web. Android and iOS can host and join (iOS hosts only while the app is open on screen). Web can only join the online server (browsers cannot run a server and need HTTPS for the mic). |
| Client technology | Flutter (one codebase for Android, iOS, web) |
| Language | Dart for app, server, rules and bots |
| Money | Starting cash ₹15,00,000 per player; ₹2,00,000 salary for passing Start |
| Card decks | Vaaippu (Chance-style) and Undiyal (Community-Chest-style) |
| Chat | Push-to-talk voice; typed chat for iPhone players only (decided 2026-11-03, because iOS cannot reliably play Opus clips) |
| Release | Internal use first; no ads, no paid version |

## 3. Multiplayer modes

All modes share one game engine and one network protocol; only where the authoritative server runs changes.

| Mode | Where the server runs | Internet needed | Players | Typical use |
| --- | --- | --- | --- | --- |
| Hotspot host | Host's phone (also provides the hotspot) | No | 2–6 | Travel, college, family gatherings |
| LAN host | Any app device on the same Wi-Fi router | No | 2–8 | Home or office Wi-Fi |
| Online server | Docker on home lab or cloud VM | Yes | 2–8 per room, many rooms | Friends in different cities |
| Vs bots | Single device, no network | No | 1 human + bots | Practice |

### Hosting (local)
- **FR-NET-1:** "Host" starts an embedded server on the host device and shows a room name, 4-digit room code and a QR code.
- **FR-NET-2:** The host plays as a normal player; the server runs in the background of their app.
- **FR-NET-3:** If no Wi-Fi or hotspot is active, guide the host to turn on the hotspot (apps cannot reliably toggle it on modern Android).

### Discovery and joining (local)
- **FR-NET-4:** Joiners see nearby games automatically via UDP broadcast and mDNS.
- **FR-NET-5:** Fallback join by scanning the QR code or typing host IP + port.
- **FR-NET-6:** Optional room password set by the host.

### Online server
- **FR-NET-7:** Server hosts many rooms; players join by room code (6 characters online) or a public lobby list.
- **FR-NET-8:** Server is self-hostable as a Docker image.
- **FR-NET-9:** The app stores a list of saved servers (name + URL).

### Host leaving
- **FR-NET-10:** If the local host leaves, the game pauses and offers to save; resuming needs the same host. Automatic host migration is out of scope for now.

## 4. Indian theme

40-tile board with 22 Indian cities in 8 colour groups, ₹ currency, Indian-flavoured cards.

| Board element | Count | Content |
| --- | --- | --- |
| Cities | 22 in 8 groups (2,3,3,3,3,3,3,2) | Patna, Bhopal · Guwahati, Bhubaneswar, Ranchi · Lucknow, Indore, Nagpur · Jaipur, Chandigarh, Kochi · Coimbatore, Visakhapatnam, Ahmedabad · Pune, Kolkata, Hyderabad · Chennai, Bengaluru, Gurugram · Delhi, Mumbai (cheapest → costliest) |
| Transport | 4 | Railways, Airline, Metro, Port (original names, no real logos) |
| Utilities | 2 | Electricity Board, Water Board |
| Card decks | 2 × 16 | Vaaippu and Undiyal — Indian events (Diwali bonus, GST refund, traffic challan, wedding gift…) |
| Corners | 4 | Start (collect salary), Jail / Just Visiting, Free Parking, Go to Jail |
| Taxes | 2 | Income Tax, Luxury Tax |

- **FR-THEME-1:** Board data (names, prices, rents, colours) loads from JSON; themes are swappable without code changes.
- **FR-THEME-2:** Currency in ₹ with Indian digit grouping (₹1,50,000).
- **FR-THEME-3:** UI in English first; Tamil and Hindi language packs later.
- **FR-THEME-4:** Optional regional board packs later (Tamil Nadu, Kerala).
- **FR-THEME-5:** Original art only; no real brand logos or Hasbro imagery.

## 5. Game rules

Server runs the full classic ruleset; house rules are host-selectable toggles.

### Turn flow
- **FR-GAME-1:** Roll two server-generated dice; doubles give another roll; a third double in a row sends the player straight to jail without moving.
- **FR-GAME-2:** Landing on an unowned property offers Buy or Auction (auction can be turned off).
- **FR-GAME-3:** Rent is automatic: base rent, double for a full colour set without buildings, 1–4 houses, hotel; transport by count owned (1–4); utilities = dice total × 4 (one owned) or × 10 (both owned), scaled to the board's currency unit; no rent on mortgaged tiles.
- **FR-GAME-4:** Passing Start pays ₹2,00,000. Starting cash ₹15,00,000. Values tunable in config.
- **FR-GAME-5:** Jail: pay ₹50,000 fine, use a get-out card, or roll doubles (max 3 tries; after the third miss, pay the fine and move).
- **FR-GAME-6:** Card draws apply automatically and are shown to all players.

### Property management
- **FR-PROP-1:** Build houses/hotels evenly across a full, unmortgaged colour set; bank limit 32 houses, 12 hotels.
- **FR-PROP-2:** Mortgage at half price; unmortgage at mortgage value + 10%.
- **FR-PROP-3:** Sell buildings back at half cost.

### Trading (player to player, no bank involved)
- **FR-TRADE-1:** Any player can propose a trade of cities, cash and get-out cards to any other player, even out of turn. Trades are applied only between phases.
- **FR-TRADE-2:** Receiver can accept, reject or counter. The server re-validates ownership and cash at accept time.
- **FR-TRADE-3:** Accept is disabled for 3 seconds after an offer appears or changes.
- **FR-TRADE-4:** Bankrupt or disconnected players cannot trade.
- **FR-TRADE-5 (optional toggles, later):** rent-immunity deals and player loans, enforced by the server.

### Bankruptcy and winning
- **FR-END-1:** A player who cannot pay must sell/mortgage/trade first; if still short they are bankrupt and assets pass to the creditor (or the bank, which auctions them).
- **FR-END-2:** Game ends when one player remains, or at a time/turn limit with the highest net worth winning.

### House-rule toggles
- Tax and fines go to a Free Parking pot; whoever lands there collects it.
- Double salary for landing exactly on Start.
- No auctions.
- No rent collected by players while in jail.
- Quick game: start with 2 random cities each, 60-minute limit.

## 6. Lobby, players and social

- **FR-LOBBY-1:** Players pick a nickname and token. No login for local play.
- **FR-LOBBY-2:** Host sees the player list, can kick, set house rules, starting cash and turn timer, and fill seats with bots.
- **FR-LOBBY-3:** Host starts when 2+ players are ready; turn order by opening roll.
- **FR-SOCIAL-1:** Quick emotes ("Aiyo!", "Semma!", thumbs up) for everyone.
- **FR-CHAT-1:** iPhone players (app and Safari) get a text box instead of the talk button. Recipients work like voice: everyone, or 1–3 players privately.
- **FR-CHAT-2:** Every player sees chat messages (feed plus a short arrival banner); Android and web cannot type.
- **FR-CHAT-3:** Max 200 characters, 1 message per second per player; per-player mute and host room-mute apply; never stored on the server or in saves.
- **FR-SOCIAL-2:** Activity log of every roll, purchase, rent, card, trade and bankruptcy, visible to all.
- **FR-RECON-1:** A dropped player can rejoin within 3 minutes using a session token; meanwhile a bot plays their turn or it auto-skips (host's choice).
- **FR-BOT-1:** Bots at Easy / Medium / Hard; Hard values colour-set completion and trades sensibly.
- **FR-SAVE-1:** Host can save and resume a local game; the online server autosaves every turn.
- **FR-SPEC-1 (later):** Spectator mode (e.g. a TV browser showing the board).

### Voice chat (walkie-talkie)
- **FR-VOICE-1:** Hold the talk button to record, release to send; max 15 s per clip.
- **FR-VOICE-2:** Before talking, pick recipients: **Broadcast** (everyone in the lobby or game, default), **one player**, or a **group of 2–3 players** (checkboxes). One-player and group clips are private. The last group used is remembered.
- **FR-VOICE-3:** Clips auto-play on arrival, queued so they never overlap; show sender name and a "private" badge when private.
- **FR-VOICE-4:** Works in the lobby and in game, fully offline on a hotspot; clips relay through the host/server over the same connection.
- **FR-VOICE-5:** Per-player mute, mute-all and volume; the host can mute a player for the whole room.
- **FR-VOICE-6:** Replay the last 5 received clips.
- **FR-VOICE-7:** Clips compressed (Opus on Android/web, AAC on iOS, ~24 kbps); max 60 KB; never stored on the server after delivery.
- **FR-VOICE-8:** Rate limit 1 clip per 3 s per player.

### Screen sizes
- **FR-UI-1:** One responsive layout from 360 px phones to tablets, laptops and TVs, portrait and landscape.
- **FR-UI-2:** Board is a scalable square; on phone portrait, panels open as slide-up sheets; on tablet/desktop as side panels.
- **FR-UI-3:** Touch targets ≥ 44 px; the talk button is thumb-reachable on every layout.

## 7. Non-functional requirements

| ID | Area | Requirement | Target |
| --- | --- | --- | --- |
| NFR-1 | Latency (local) | Action to all-player update | < 150 ms |
| NFR-2 | Latency (online) | Action to all-player update | < 500 ms |
| NFR-3 | Fairness | Server-only CSPRNG dice with commit–reveal | Every roll verifiable in the log |
| NFR-4 | Anti-cheat | Clients send intents only; server validates every action | Zero client-trusted state |
| NFR-5 | Reliability | Reconnect after Wi-Fi drop or app background | Seat restored within 3 min |
| NFR-6 | Devices | Android 9+ with 3 GB RAM; iOS; modern browsers | 30 fps board animation |
| NFR-7 | Battery | Host phone running server + hotspot, 90-min game | < 25% battery |
| NFR-8 | Online capacity (internal) | Rooms on one server (2 vCPU, 4 GB) | ≥ 200 rooms (target 1,000 in testing) |
| NFR-9 | Security | Room passwords, rate-limited joins, TLS online | 5 wrong attempts → 1-min block |
| NFR-10 | Offline | Local modes with internet fully off | 100% functional |
| NFR-11 | Privacy | No personal data collected for local play | — |
| NFR-12 | Scalability | Online design can grow to 100 million users | See `design.md` §10 |

## 8. Out of scope (for internal release)

Ads, payments, accounts/sign-in, automatic host migration, spectator mode, language packs, regional boards, AI-powered bots. These may come later.
