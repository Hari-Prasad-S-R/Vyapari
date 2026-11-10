import 'dart:async';
import 'dart:typed_data';

import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import 'support.dart';

/// Result of a hello against this room.
class JoinOutcome {
  const JoinOutcome._(this.playerId, this.error);

  /// Joined as [playerId].
  const JoinOutcome.ok(String playerId) : this._(playerId, null);

  /// Refused with [error].
  const JoinOutcome.refused(ErrorCode error) : this._(null, error);

  /// Seat id on success.
  final String? playerId;

  /// Reason on failure.
  final ErrorCode? error;
}

/// One game room: the authoritative state plus everyone connected to it.
///
/// All game changes go through the rules engine; this class only routes
/// messages, rolls dice, runs bots and timers, and relays voice.
class Room {
  /// Creates a room for [board].
  Room({
    required this.code,
    required BoardData board,
    required this.config,
    required this.rng,
    this.password,
    this.isLocal = true,
    this.clock = systemClock,
    this.onSave,
    this.onEmpty,
  })  : state = newLobby(roomId: code, board: board),
        _board = board,
        dice = FairDice(rng) {
    _voiceLimiter = RateLimiter(config.voiceInterval, clock);
    _emoteLimiter = RateLimiter(const Duration(milliseconds: 800), clock);
    _chatLimiter = RateLimiter(const Duration(milliseconds: 1000), clock);
  }

  /// Room code.
  final String code;
  final BoardData _board;

  /// Server tunables.
  final ServerConfig config;

  /// Secure randomness for dice, seeds and tokens.
  final RandomSource rng;

  /// Optional room password.
  final String? password;

  /// Local host mode: the game pauses when the host leaves.
  final bool isLocal;

  /// Clock.
  final Clock clock;

  /// Called with a snapshot whenever the room should be saved.
  final void Function(Room room)? onSave;

  /// Called when the last human leaves an unstarted room.
  final void Function(Room room)? onEmpty;

  /// Authoritative state.
  GameState state;

  /// Fair dice for this game.
  FairDice dice;

  /// Whether play is paused (local host left).
  bool paused = false;

  /// Session token → seat.
  final Map<String, String> sessions = {};
  final Map<String, Peer> _peers = {};
  final Map<String, int> _lastSeen = {};
  final Map<String, Timer> _rejoinTimers = {};
  final Map<String, Bot> _bots = {};
  final Map<String, int> _tradeSeenAt = {};

  /// Players muted room-wide by the host.
  final Set<String> mutedRoomWide = {};
  late final RateLimiter _voiceLimiter;
  late final RateLimiter _emoteLimiter;
  late final RateLimiter _chatLimiter;
  int _chatSeq = 0;
  final Map<int, DiceCommit> _commits = {};
  final List<DiceReveal> _reveals = [];
  Timer? _botTimer;
  Timer? _auctionTimer;
  Timer? _turnTimer;
  String? _turnKey;
  String? _timedOutKey;
  int _seat = 0;
  int _lastSavedTurn = -1;
  bool _disposed = false;

  /// Connected player ids.
  Iterable<String> get connectedIds => _peers.keys;

  /// Every dice commit and reveal so far (for the Verify dice view).
  List<(DiceCommit?, DiceReveal)> get diceHistory =>
      [for (final r in _reveals) (_commits[r.rollNumber], r)];

  // ---------------------------------------------------------------- joining

  /// Handles a validated hello from [peer].
  JoinOutcome join(Peer peer, Hello h) {
    final token = h.sessionToken;
    if (token != null && sessions.containsKey(token)) {
      final id = sessions[token]!;
      final p = state.player(id);
      if (p != null && _humans.contains(id)) {
        _attach(id, peer, token);
        _rejoinTimers.remove(id)?.cancel();
        if (!p.connected) _apply(SetConnected(id, connected: true));
        if (paused && id == state.hostId) {
          paused = false;
          broadcast(const NoticeMsg('resumed', text: 'The host is back'));
        }
        _sendCommit(id);
        return JoinOutcome.ok(id);
      }
    }
    if (state.phase != GamePhase.lobby) {
      return const JoinOutcome.refused(ErrorCode.illegalPhase);
    }
    if (state.players.length >= state.config.maxPlayers) {
      return const JoinOutcome.refused(ErrorCode.roomFull);
    }
    final id = 's${++_seat}';
    final r = apply(JoinGame(id, name: h.name, token: h.token), state);
    if (!r.ok) return JoinOutcome.refused(r.error!);
    final token0 = newToken(rng);
    sessions[token0] = id;
    _humans.add(id);
    _commit(r);
    _attach(id, peer, token0);
    return JoinOutcome.ok(id);
  }

  final Set<String> _humans = {};

  void _attach(String id, Peer peer, String token) {
    final old = _peers[id];
    if (old != null && !identical(old, peer)) old.close();
    _peers[id] = peer;
    _lastSeen[id] = clock();
    _sendMsg(
        peer,
        Welcome(
            playerId: id,
            sessionToken: token,
            state: state,
            password: password != null));
  }

  // ---------------------------------------------------------------- input

  /// Handles a decoded text message from [playerId].
  void onMessage(String playerId, Envelope env) {
    if (_disposed) return;
    _lastSeen[playerId] = clock();
    final m = env.message;
    if (m is! ClientMessage || m is Hello) {
      _error(playerId, ErrorCode.unknownMessage, env.id);
      return;
    }
    final type = m.type;
    // Messages that are not game actions.
    switch (type) {
      case 'ping':
        _send(playerId, const NoticeMsg('pong'));
        return;
      case 'sync':
        _send(playerId, StateMsg(state));
        return;
      case 'emote':
        if (!_emoteLimiter.tryAcquire(playerId)) {
          _error(playerId, ErrorCode.rateLimited, env.id);
          return;
        }
        broadcast(EmoteBroadcast(from: playerId, emote: (m as EmoteMsg).emote));
        return;
      case 'chat':
        final error = onChat(playerId, m as ChatMsg);
        if (error != null) _error(playerId, error, env.id);
        return;
      case 'mute_player':
        final t = m as PlayerTargetMsg;
        if (state.hostId != playerId) {
          _error(playerId, ErrorCode.hostOnly, env.id);
          return;
        }
        if (t.flag ?? true) {
          mutedRoomWide.add(t.playerId);
        } else {
          mutedRoomWide.remove(t.playerId);
        }
        broadcast(NoticeMsg('muted',
            data: {'playerId': t.playerId, 'muted': t.flag ?? true}));
        return;
      case 'save_game':
        if (state.hostId != playerId) {
          _error(playerId, ErrorCode.hostOnly, env.id);
          return;
        }
        save();
        broadcast(const NoticeMsg('saved', text: 'Game saved'));
        return;
      case 'rematch':
        if (state.hostId != playerId) {
          _error(playerId, ErrorCode.hostOnly, env.id);
          return;
        }
        if (state.phase != GamePhase.gameOver) {
          _error(playerId, ErrorCode.illegalPhase, env.id);
          return;
        }
        _rematch();
        return;
    }
    if (paused) {
      _error(playerId, ErrorCode.illegalPhase, env.id, 'Game is paused');
      return;
    }
    if (type == 'trade_accept' && _humans.contains(playerId)) {
      final seen = _tradeSeenAt[(m as TradeAnswerMsg).tradeId];
      if (seen != null &&
          clock() - seen < config.tradeReviewDelay.inMilliseconds) {
        _error(
            playerId, ErrorCode.rateLimited, env.id, 'Review the offer first');
        return;
      }
    }
    final action = _toAction(playerId, m);
    if (action == null) {
      _error(playerId, ErrorCode.unknownMessage, env.id);
      return;
    }
    final error = _apply(action, refId: env.id);
    if (error != null) {
      _error(playerId, error, env.id);
      return;
    }
    if (type == 'kick') {
      final target = (m as PlayerTargetMsg).playerId;
      final peer = _peers.remove(target);
      if (peer != null) {
        _sendMsg(peer, const NoticeMsg('kicked', text: 'The host removed you'));
        peer.close();
      }
      sessions.removeWhere((_, id) => id == target);
    }
    if (type == 'leave') {
      _peers.remove(playerId)?.close();
      sessions.removeWhere((_, id) => id == playerId);
      _checkEmpty();
    }
  }

  GameAction? _toAction(String me, ClientMessage m) {
    switch (m) {
      case ReadyMsg():
        return SetReady(me, ready: m.ready);
      case SetRulesMsg():
        return SetRules(me, m.rules);
      case AddBotMsg():
        final id = 'b${++_seat}';
        final used = state.players.map((p) => p.token).toSet();
        final token = Token.values.firstWhere((t) => !used.contains(t),
            orElse: () => Token.values[_seat % Token.values.length]);
        final names = state.players.map((p) => p.name).toSet();
        final name = botNames.firstWhere((n) => !names.contains(n),
            orElse: () => 'Bot $_seat');
        return AddBot(me, botId: id, name: name, token: token, level: m.level);
      case PlayerTargetMsg(type: 'kick'):
        return Kick(me, m.playerId);
      case SimpleIntent(type: 'start'):
        final rolls = <String, int>{};
        for (final p in state.players) {
          final r = dice.roll();
          rolls[p.id] = r.total;
        }
        return StartGame(me, seed: rng.nextInt(1 << 31), openingRolls: rolls);
      case SimpleIntent(type: 'roll'):
        return Roll.intent(me);
      case SimpleIntent(type: 'buy'):
        return Buy(me);
      case SimpleIntent(type: 'decline'):
        return DeclineBuy(me,
            endsAt: clock() + config.auctionTime.inMilliseconds);
      case BidMsg():
        return Bid(me, m.amount,
            endsAt: clock() + config.auctionTime.inMilliseconds);
      case SimpleIntent(type: 'pay_jail'):
        return PayJailFine(me);
      case SimpleIntent(type: 'use_card'):
        return UseJailCard(me);
      case SimpleIntent(type: 'end_turn'):
        return EndTurn(me);
      case SimpleIntent(type: 'pay_debt'):
        return PayDebt(me);
      case SimpleIntent(type: 'declare_bankruptcy'):
        return DeclareBankruptcy(me);
      case SimpleIntent(type: 'leave'):
        return LeaveGame(me);
      case TileMsg(type: 'build'):
        return Build(me, m.tile);
      case TileMsg(type: 'sell_building'):
        return SellBuilding(me, m.tile);
      case TileMsg(type: 'mortgage'):
        return Mortgage(me, m.tile);
      case TileMsg(type: 'unmortgage'):
        return Unmortgage(me, m.tile);
      case TradeProposeMsg():
        return ProposeTrade(me, to: m.to, give: m.give, get: m.get);
      case TradeAnswerMsg(type: 'trade_accept'):
        return AcceptTrade(me, m.tradeId);
      case TradeAnswerMsg(type: 'trade_reject'):
        return RejectTrade(me, m.tradeId);
      case TradeAnswerMsg(type: 'trade_cancel'):
        return CancelTrade(me, m.tradeId);
      case TradeCounterMsg():
        return CounterTrade(me, m.tradeId, give: m.give, get: m.get);
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------- chat

  /// Relays a typed chat message from [from] to everyone or to 1–3 chosen
  /// players. Like voice, it is held in memory only and never saved.
  ErrorCode? onChat(String from, ChatMsg m) {
    final text = m.text.trim();
    if (text.isEmpty || text.length > maxChatLength) {
      return ErrorCode.invalidAction;
    }
    final to = m.to.toSet();
    if (to.length > 3 ||
        to.contains(from) ||
        to.any((id) => state.player(id) == null)) {
      return ErrorCode.invalidAction;
    }
    if (!_chatLimiter.tryAcquire(from)) return ErrorCode.rateLimited;
    // A room-muted player's messages reach nobody.
    if (mutedRoomWide.contains(from)) return null;
    final out = ChatBroadcast(
        id: 'm${++_chatSeq}', from: from, text: text, to: to.toList());
    if (to.isEmpty) {
      broadcast(out);
    } else {
      // The sender gets a copy so their own chat shows the message.
      for (final id in {...to, from}) {
        _send(id, out);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- voice

  /// Relays a voice clip from [from]. Returns an error code if refused.
  ErrorCode? onVoice(String from, Uint8List bytes) {
    if (_disposed) return ErrorCode.illegalPhase;
    _lastSeen[from] = clock();
    if (bytes.length >
        VoiceFrame.maxAudioBytes + VoiceFrame.maxHeaderBytes + 4) {
      return _voiceError(from, ErrorCode.invalidAction, 'Clip too large');
    }
    final frame = VoiceFrame.decode(bytes);
    if (frame == null) {
      return _voiceError(from, ErrorCode.malformed, 'Bad clip');
    }
    if (frame.audio.length > VoiceFrame.maxAudioBytes) {
      return _voiceError(from, ErrorCode.invalidAction, 'Clip too large');
    }
    if (frame.header.durationMs > VoiceFrame.maxDurationMs + 500) {
      return _voiceError(from, ErrorCode.invalidAction, 'Clip too long');
    }
    final to = frame.header.to.toSet();
    if (to.length > 3 ||
        to.contains(from) ||
        to.any((id) => state.player(id) == null)) {
      return _voiceError(from, ErrorCode.invalidAction, 'Unknown recipients');
    }
    if (!_voiceLimiter.tryAcquire(from)) {
      return _voiceError(from, ErrorCode.rateLimited, 'One clip every 3 s');
    }
    // A muted sender's clip is dropped silently; nobody receives it.
    if (mutedRoomWide.contains(from)) return null;
    final out = VoiceFrame(
            frame.header.copyWith(from: from, to: to.toList()), frame.audio)
        .encode();
    final recipients = to.isEmpty
        ? _peers.keys.where((id) => id != from).toList()
        : to.where(_peers.containsKey).toList();
    for (final id in recipients) {
      _peers[id]?.sendBinary(out);
    }
    // Nothing is kept: the clip goes out of scope here.
    return null;
  }

  ErrorCode _voiceError(String id, ErrorCode code, String why) {
    _error(id, code, null, why);
    return code;
  }

  // ---------------------------------------------------------------- connection

  /// A peer's socket closed.
  void onClosed(String playerId, Peer peer) {
    if (_disposed) return;
    if (!identical(_peers[playerId], peer)) return;
    _peers.remove(playerId);
    _markDisconnected(playerId);
  }

  void _markDisconnected(String id) {
    final p = state.player(id);
    if (p == null) return;
    if (p.connected && state.phase != GamePhase.gameOver) {
      _apply(SetConnected(id, connected: false));
    }
    if (isLocal &&
        id == state.hostId &&
        state.phase != GamePhase.lobby &&
        state.phase != GamePhase.gameOver) {
      paused = true;
      save();
      broadcast(const NoticeMsg('paused',
          text: 'The host left. The game is paused and saved.',
          data: {'canSave': true}));
    }
    _rejoinTimers[id]?.cancel();
    _rejoinTimers[id] = Timer(config.rejoinWindow, () => _rejoinExpired(id));
    _checkEmpty();
  }

  void _rejoinExpired(String id) {
    _rejoinTimers.remove(id);
    if (_disposed || _peers.containsKey(id)) return;
    sessions.removeWhere((_, pid) => pid == id);
    final p = state.player(id);
    if (p == null) return;
    if (state.phase == GamePhase.lobby) {
      _apply(LeaveGame(id));
    } else if (!p.bankrupt && state.phase != GamePhase.gameOver) {
      _humans.remove(id);
      _apply(ReplaceWithBot(id));
    }
  }

  /// Drops connections that missed heartbeats.
  void sweepHeartbeats() {
    final now = clock();
    for (final id in _peers.keys.toList()) {
      final seen = _lastSeen[id] ?? now;
      if (now - seen > config.heartbeatTimeout.inMilliseconds) {
        final peer = _peers.remove(id);
        peer?.close();
        _markDisconnected(id);
      }
    }
  }

  void _checkEmpty() {
    if (_peers.isEmpty && state.phase == GamePhase.lobby) {
      if (!state.players.any((p) => !p.isBot && p.connected)) {
        onEmpty?.call(this);
      }
    }
  }

  // ---------------------------------------------------------------- core loop

  /// Applies [action] through the rules engine and broadcasts the result.
  /// Returns the error code if rejected.
  ErrorCode? _apply(GameAction action, {String? refId}) {
    var a = action;
    DiceReveal? reveal;
    if (a is Roll && !a.hasDice) {
      // Validate before consuming dice so rejected rolls keep the commit.
      final probe = apply(Roll(a.playerId, 1, 2), state);
      if (!probe.ok) return probe.error;
      reveal = dice.roll();
      a = Roll(a.playerId, reveal.d1, reveal.d2);
    }
    final r = apply(a, state);
    if (!r.ok) return r.error;
    if (reveal != null) {
      _reveals.add(reveal);
      broadcast(DiceRevealMsg(reveal));
    }
    _commit(r);
    if (reveal != null) _broadcastCommit();
    return null;
  }

  void _commit(ApplyResult r) {
    final prev = state;
    state = r.state;
    _pendingAnimation =
        config.paceAnimations ? animationTime(r.events) : Duration.zero;
    broadcast(PatchMsg.diff(prev, state, r.events));
    if (prev.phase == GamePhase.lobby && state.phase != GamePhase.lobby) {
      _broadcastCommit();
    }
    _afterChange(prev);
  }

  void _broadcastCommit() {
    final c = dice.nextCommit;
    _commits[c.rollNumber] = c;
    broadcast(DiceCommitMsg(c));
  }

  void _sendCommit(String id) {
    if (state.phase == GamePhase.lobby) return;
    _send(id, DiceCommitMsg(dice.nextCommit));
  }

  void _afterChange(GameState prev) {
    final now = clock();
    for (final t in state.trades) {
      _tradeSeenAt.putIfAbsent(t.id, () => now);
    }
    _tradeSeenAt.removeWhere((id, _) => !state.trades.any((t) => t.id == id));
    _syncBots();
    _syncAuctionTimer(prev);
    _syncTurnTimer();
    if (state.turnNumber != _lastSavedTurn && state.phase != GamePhase.lobby) {
      _lastSavedTurn = state.turnNumber;
      save();
    }
    if (state.phase == GamePhase.gameOver && prev.phase != GamePhase.gameOver) {
      save();
    }
    _scheduleBots();
  }

  void _syncBots() {
    for (final p in state.players) {
      if (p.isBot && !_bots.containsKey(p.id)) {
        _bots[p.id] = Bot.forLevel(p.botLevel ?? BotLevel.medium, rng);
      }
    }
  }

  void _syncAuctionTimer(GameState prev) {
    final auc = state.auction;
    if (auc == null) {
      _auctionTimer?.cancel();
      _auctionTimer = null;
      return;
    }
    final changed = prev.auction == null ||
        prev.auction!.bids.length != auc.bids.length ||
        prev.auction!.highBid != auc.highBid;
    if (!changed && _auctionTimer != null) return;
    _auctionTimer?.cancel();
    final everyoneAuto = state.activePlayers.every((p) => _isAuto(p.id));
    final wait = everyoneAuto ? config.botDelay : config.auctionTime;
    _auctionTimer = Timer(wait, () {
      _auctionTimer = null;
      if (_disposed || paused || state.auction == null) return;
      // Give bots a last chance to outbid before closing.
      if (_botAuctionStep()) return;
      _apply(CloseAuction(state.currentPlayer ?? ''));
    });
  }

  void _syncTurnTimer() {
    final key = _turnKey0();
    final sec = state.rules.turnTimerSec;
    final inPlay =
        state.phase != GamePhase.lobby && state.phase != GamePhase.gameOver;
    if (!config.enableTurnTimer || sec <= 0 || !inPlay) {
      _turnTimer?.cancel();
      _turnTimer = null;
      _turnKey = null;
      return;
    }
    if (key == _turnKey) return;
    _turnKey = key;
    _timedOutKey = null;
    _turnTimer?.cancel();
    _turnTimer = Timer(Duration(seconds: sec), () {
      if (_disposed || _turnKey != key) return;
      _timedOutKey = key;
      broadcast(NoticeMsg('timeout',
          text: "Time's up — the turn is being finished",
          data: {'playerId': _actor}));
      _scheduleBots(immediate: true);
    });
  }

  /// Who must act now: a debtor raising cash, else the current player.
  String? get _actor => state.actingPlayer ?? state.currentPlayer;

  /// Timer key: a new turn, or a different player raising cash, gets a
  /// fresh turn timer.
  String _turnKey0() =>
      '$_actor:${state.turnNumber}:${state.phase == GamePhase.raiseCash}';

  /// Turn time-out uses a cautious autopilot that never buys.
  late final Bot _autopilot = _AutoPilot(rng);

  bool _isAuto(String id) {
    final p = state.player(id);
    if (p == null || p.bankrupt) return false;
    return p.isBot || !p.connected;
  }

  Bot? _controllerFor(String id) {
    final p = state.player(id);
    if (p == null || p.bankrupt) return null;
    if (p.isBot) return _bots[id];
    if (!p.connected) {
      return state.rules.botCover
          ? _bots.putIfAbsent('cover:$id', () => MediumBot(rng))
          : _autopilot;
    }
    if (id == _actor && _timedOutKey == _turnKey0()) {
      return _autopilot;
    }
    return null;
  }

  void _scheduleBots({bool immediate = false}) {
    _botTimer?.cancel();
    if (_disposed || paused) return;
    if (state.phase == GamePhase.lobby || state.phase == GamePhase.gameOver) {
      return;
    }
    _botTimer = Timer(
        immediate ? Duration.zero : config.botDelay + _pendingAnimation,
        _botStep);
  }

  /// Animation time of the last change, waited before the next bot move.
  Duration _pendingAnimation = Duration.zero;

  /// One bot step: returns whether an action was applied.
  bool _botStep() {
    _botTimer = null;
    if (_disposed || paused) return false;
    if (state.phase == GamePhase.auction) return _botAuctionStep();
    for (final t in state.trades) {
      final bot = _controllerFor(t.to);
      if (bot != null && _runBot(bot, t.to)) return true;
    }
    final cur = _actor;
    if (cur == null) return false;
    final bot = _controllerFor(cur);
    if (bot == null) return false;
    if (_runBot(bot, cur)) return true;
    return false;
  }

  bool _botAuctionStep() {
    final ids = state.activePlayers.map((p) => p.id).toList();
    for (final id in ids) {
      final bot = _controllerFor(id);
      if (bot == null) continue;
      if (_runBot(bot, id)) return true;
    }
    return false;
  }

  bool _runBot(Bot bot, String id) {
    for (final candidate in bot.candidates(state, id)) {
      var a = candidate;
      DiceReveal? reveal;
      if (a is Roll && !a.hasDice) {
        // Never consume committed dice for a roll the engine would reject.
        if (!apply(Roll(id, 1, 2), state).ok) continue;
        reveal = dice.roll();
        a = Roll(id, reveal.d1, reveal.d2);
      }
      final r = apply(a, state);
      if (!r.ok) continue;
      if (reveal != null) {
        _reveals.add(reveal);
        broadcast(DiceRevealMsg(reveal));
      }
      _commit(r);
      if (reveal != null) _broadcastCommit();
      return true;
    }
    return false;
  }

  void _rematch() {
    final old = state.players;
    var s = newLobby(roomId: code, board: _board, rules: state.rules);
    final host = state.hostId;
    final ordered = [
      ...old.where((p) => p.id == host),
      ...old.where((p) => p.id != host),
    ];
    for (final p in ordered) {
      final human = _humans.contains(p.id);
      final GameAction a = human
          ? JoinGame(p.id, name: p.name, token: p.token)
          : AddBot(host ?? p.id,
              botId: p.id,
              name: p.name,
              token: p.token,
              level: p.botLevel ?? BotLevel.medium);
      final r = apply(a, s);
      if (r.ok) s = r.state;
      if (human && !_peers.containsKey(p.id) && r.ok) {
        s = apply(SetConnected(p.id, connected: false), s).state;
      }
    }
    final prev = state;
    state = s.copyWith(version: prev.version + 1);
    dice = FairDice(rng);
    _commits.clear();
    _reveals.clear();
    _lastSavedTurn = -1;
    _bots.clear();
    broadcast(StateMsg(state));
    broadcast(const NoticeMsg('rematch', text: 'New game — same players'));
    _afterChange(prev);
  }

  // ---------------------------------------------------------------- output

  /// Sends [m] to every connected player.
  void broadcast(ServerMessage m) {
    final text = Envelope(m, room: code).encode();
    for (final p in _peers.values) {
      p.sendText(text);
    }
  }

  void _send(String id, ServerMessage m) {
    final peer = _peers[id];
    if (peer != null) _sendMsg(peer, m);
  }

  void _sendMsg(Peer peer, ServerMessage m) =>
      peer.sendText(Envelope(m, room: code).encode());

  void _error(String id, ErrorCode code, String? refId,
          [String message = '']) =>
      _send(id, ErrorMsg(code, refId: refId, message: message));

  // ---------------------------------------------------------------- saving

  /// Snapshot for saving (never includes voice).
  Map<String, Object?> snapshot() => {
        'code': code,
        'state': state.toJson(),
        'sessions': sessions,
        'humans': _humans.toList(),
        'password': password,
        'isLocal': isLocal,
        'seat': _seat,
      };

  /// Saves now via [onSave].
  void save() => onSave?.call(this);

  /// Restores a saved room. Everyone starts disconnected and rejoins with
  /// their session token.
  static Room restore(
    Map<String, Object?> json, {
    required BoardData board,
    required ServerConfig config,
    required RandomSource rng,
    Clock clock = systemClock,
    void Function(Room)? onSave,
    void Function(Room)? onEmpty,
  }) {
    final room = Room(
      code: json['code'] as String,
      board: board,
      config: config,
      rng: rng,
      password: json['password'] as String?,
      isLocal: json['isLocal'] as bool? ?? true,
      clock: clock,
      onSave: onSave,
      onEmpty: onEmpty,
    );
    var s = GameState.fromJson((json['state'] as Map).cast());
    room.sessions.addAll((json['sessions'] as Map).cast<String, String>());
    room._humans.addAll((json['humans'] as List).cast<String>());
    room._seat = json['seat'] as int? ?? 0;
    for (final p in s.players.where((p) => !p.isBot && p.connected)) {
      s = apply(SetConnected(p.id, connected: false), s).state;
    }
    room.state = s;
    room._lastSavedTurn = s.turnNumber;
    room._syncBots();
    if (room.isLocal &&
        s.phase != GamePhase.lobby &&
        s.phase != GamePhase.gameOver) {
      room.paused = true;
    }
    for (final p in s.players.where((p) => !p.isBot)) {
      room._rejoinTimers[p.id] =
          Timer(config.rejoinWindow, () => room._rejoinExpired(p.id));
    }
    return room;
  }

  /// Stops timers and closes connections.
  void dispose() {
    _disposed = true;
    _botTimer?.cancel();
    _auctionTimer?.cancel();
    _turnTimer?.cancel();
    for (final t in _rejoinTimers.values) {
      t.cancel();
    }
    for (final p in _peers.values) {
      p.close();
    }
    _peers.clear();
  }
}

/// Finishes a timed-out or uncovered turn safely: rolls, never buys, never
/// bids, raises cash only when forced.
class _AutoPilot extends MediumBot {
  _AutoPilot(super.rng);

  @override
  bool shouldBuy(GameState s, Player p, Tile tile) => false;

  @override
  int? auctionBid(GameState s, String me) => null;

  @override
  List<GameAction> buildChoices(GameState s, Player p) => const [];

  @override
  List<GameAction> unmortgageChoices(GameState s, Player p) => const [];

  @override
  List<GameAction> jailChoice(GameState s, Player p) => const [];

  @override
  bool judgeTrade(GameState s, String me, Trade t) => false;
}
