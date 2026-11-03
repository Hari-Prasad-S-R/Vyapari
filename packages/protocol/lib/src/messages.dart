import 'package:vyapari_core/vyapari_core.dart';

/// Protocol version carried in every envelope.
const protocolVersion = 1;

/// Fixed emotes (no typed chat anywhere).
enum Emote {
  aiyo('Aiyo!'),
  semma('Semma!'),
  thumbsUp('👍'),
  clap('👏'),
  wow('Wah!');

  const Emote(this.label);

  /// Text shown over the sender's token.
  final String label;
}

/// A protocol message. [type] is its wire name; [toData] its `data` object.
sealed class Message {
  const Message();

  /// Wire type, e.g. `roll`.
  String get type;

  /// The envelope's `data` object.
  Map<String, Object?> toData() => const {};

  @override
  bool operator ==(Object other) =>
      other is Message &&
      other.type == type &&
      _jsonEq(other.toData(), toData());

  @override
  int get hashCode => type.hashCode;

  @override
  String toString() => '$type${toData()}';
}

bool _jsonEq(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Client → server.
sealed class ClientMessage extends Message {
  const ClientMessage();
}

/// Server → client.
sealed class ServerMessage extends Message {
  const ServerMessage();
}

/// A client message with no payload.
final class SimpleIntent extends ClientMessage {
  /// Creates an intent of [type].
  const SimpleIntent(this.type);

  @override
  final String type;

  /// Wire types that carry no data.
  static const types = {
    'start',
    'roll',
    'buy',
    'decline',
    'pay_jail',
    'use_card',
    'end_turn',
    'pay_debt',
    'declare_bankruptcy',
    'ping',
    'leave',
    'save_game',
    'rematch',
  };
}

// ---------------------------------------------------------------- client

/// First message on a connection: join, create or rejoin a room.
final class Hello extends ClientMessage {
  /// Creates a hello.
  const Hello({
    required this.name,
    required this.token,
    this.sessionToken,
    this.lastVersion,
    this.create = false,
    this.password,
    this.deviceName = '',
  });

  @override
  String get type => 'hello';

  /// Nickname.
  final String name;

  /// Chosen token.
  final Token token;

  /// Session token when rejoining.
  final String? sessionToken;

  /// Last state version the client saw.
  final int? lastVersion;

  /// Create a new room (online) instead of joining the envelope's room.
  final bool create;

  /// Room password, if required.
  final String? password;

  /// Device label.
  final String deviceName;

  @override
  Map<String, Object?> toData() => {
        'name': name,
        'token': token.name,
        if (sessionToken != null) 'sessionToken': sessionToken,
        if (lastVersion != null) 'lastVersion': lastVersion,
        if (create) 'create': true,
        if (password != null) 'password': password,
        if (deviceName.isNotEmpty) 'deviceName': deviceName,
      };

  static Hello _decode(Map<String, Object?> d) => Hello(
        name: d['name'] as String,
        token: Token.values.byName(d['token'] as String),
        sessionToken: d['sessionToken'] as String?,
        lastVersion: d['lastVersion'] as int?,
        create: d['create'] as bool? ?? false,
        password: d['password'] as String?,
        deviceName: d['deviceName'] as String? ?? '',
      );
}

/// Lobby ready tick.
final class ReadyMsg extends ClientMessage {
  /// Creates the message.
  const ReadyMsg({required this.ready});

  @override
  String get type => 'ready';

  /// Ready value.
  final bool ready;

  @override
  Map<String, Object?> toData() => {'ready': ready};
}

/// Host sets house rules.
final class SetRulesMsg extends ClientMessage {
  /// Creates the message.
  const SetRulesMsg(this.rules);

  @override
  String get type => 'set_rules';

  /// New rules.
  final HouseRules rules;

  @override
  Map<String, Object?> toData() => rules.toJson();
}

/// Host adds a bot.
final class AddBotMsg extends ClientMessage {
  /// Creates the message.
  const AddBotMsg({this.level = BotLevel.medium});

  @override
  String get type => 'add_bot';

  /// Difficulty.
  final BotLevel level;

  @override
  Map<String, Object?> toData() => {'level': level.name};
}

/// A message that targets one player: `kick`, `mute_player`.
final class PlayerTargetMsg extends ClientMessage {
  /// Creates the message.
  const PlayerTargetMsg(this.type, this.playerId, {this.flag});

  @override
  final String type;

  /// Target player.
  final String playerId;

  /// For `mute_player`: muted or not.
  final bool? flag;

  @override
  Map<String, Object?> toData() =>
      {'playerId': playerId, if (flag != null) 'muted': flag};
}

/// Bid in an auction.
final class BidMsg extends ClientMessage {
  /// Creates the message.
  const BidMsg(this.amount);

  @override
  String get type => 'bid';

  /// Amount in rupees.
  final int amount;

  @override
  Map<String, Object?> toData() => {'amount': amount};
}

/// Property action on one tile: `build`, `sell_building`, `mortgage`,
/// `unmortgage`.
final class TileMsg extends ClientMessage {
  /// Creates the message.
  const TileMsg(this.type, this.tile);

  @override
  final String type;

  /// Tile index.
  final int tile;

  @override
  Map<String, Object?> toData() => {'tile': tile};

  /// Valid wire types.
  static const types = {'build', 'sell_building', 'mortgage', 'unmortgage'};
}

/// Propose a trade.
final class TradeProposeMsg extends ClientMessage {
  /// Creates the message.
  const TradeProposeMsg(
      {required this.to, required this.give, required this.get});

  @override
  String get type => 'trade_propose';

  /// Receiver.
  final String to;

  /// What I give.
  final TradeSide give;

  /// What I get.
  final TradeSide get;

  @override
  Map<String, Object?> toData() =>
      {'to': to, 'give': give.toJson(), 'get': get.toJson()};
}

/// Answer a trade: `trade_accept`, `trade_reject`, `trade_cancel`.
final class TradeAnswerMsg extends ClientMessage {
  /// Creates the message.
  const TradeAnswerMsg(this.type, this.tradeId);

  @override
  final String type;

  /// Trade id.
  final String tradeId;

  @override
  Map<String, Object?> toData() => {'tradeId': tradeId};

  /// Valid wire types.
  static const types = {'trade_accept', 'trade_reject', 'trade_cancel'};
}

/// Counter a trade.
final class TradeCounterMsg extends ClientMessage {
  /// Creates the message.
  const TradeCounterMsg(this.tradeId, {required this.give, required this.get});

  @override
  String get type => 'trade_counter';

  /// Trade being countered.
  final String tradeId;

  /// What I give.
  final TradeSide give;

  /// What I get.
  final TradeSide get;

  @override
  Map<String, Object?> toData() =>
      {'tradeId': tradeId, 'give': give.toJson(), 'get': get.toJson()};
}

/// Send a fixed emote.
final class EmoteMsg extends ClientMessage {
  /// Creates the message.
  const EmoteMsg(this.emote);

  @override
  String get type => 'emote';

  /// Emote.
  final Emote emote;

  @override
  Map<String, Object?> toData() => {'emote': emote.name};
}

/// Ask for a full state resync.
final class SyncMsg extends ClientMessage {
  /// Creates the message.
  const SyncMsg(this.lastVersion);

  @override
  String get type => 'sync';

  /// Last version seen.
  final int lastVersion;

  @override
  Map<String, Object?> toData() => {'lastVersion': lastVersion};
}

// ---------------------------------------------------------------- server

/// Accepted hello: seat, session token and full state.
final class Welcome extends ServerMessage {
  /// Creates the message.
  const Welcome(
      {required this.playerId,
      required this.sessionToken,
      required this.state,
      this.password = false});

  @override
  String get type => 'welcome';

  /// Your seat id.
  final String playerId;

  /// Token to rejoin this seat.
  final String sessionToken;

  /// Full state.
  final GameState state;

  /// Whether the room has a password.
  final bool password;

  @override
  Map<String, Object?> toData() => {
        'playerId': playerId,
        'sessionToken': sessionToken,
        'state': state.toJson(),
        if (password) 'password': true,
      };
}

/// Full state (join, reconnect, version gap).
final class StateMsg extends ServerMessage {
  /// Creates the message.
  const StateMsg(this.state);

  @override
  String get type => 'state';

  /// Full state.
  final GameState state;

  @override
  Map<String, Object?> toData() => {'state': state.toJson()};
}

/// Top-level state fields that changed since [fromVersion], plus events.
final class PatchMsg extends ServerMessage {
  /// Creates the message.
  const PatchMsg({
    required this.fromVersion,
    required this.toVersion,
    required this.changes,
    this.events = const [],
  });

  /// Builds a patch from [before] to [after].
  factory PatchMsg.diff(GameState before, GameState after,
      [List<GameEvent> events = const []]) {
    final a = before.toJson();
    final b = after.toJson();
    final changes = <String, Object?>{};
    for (final k in b.keys) {
      if (!_jsonEq(a[k], b[k])) changes[k] = b[k];
    }
    return PatchMsg(
      fromVersion: before.version,
      toVersion: after.version,
      changes: changes,
      events: events,
    );
  }

  @override
  String get type => 'patch';

  /// Version the patch applies to.
  final int fromVersion;

  /// Version after applying.
  final int toVersion;

  /// Changed top-level state fields with their new JSON values.
  final Map<String, Object?> changes;

  /// Events to animate and log.
  final List<GameEvent> events;

  /// Applies this patch to [state]. Returns `null` if versions do not line
  /// up (the caller should ignore stale patches and resync on gaps).
  GameState? applyTo(GameState state) {
    if (state.version != fromVersion) return null;
    final json = {...state.toJson(), ...changes};
    return GameState.fromJson(json);
  }

  @override
  Map<String, Object?> toData() => {
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'changes': changes,
        'events': [for (final e in events) e.toJson()],
      };
}

/// Fair-dice commit before a roll.
final class DiceCommitMsg extends ServerMessage {
  /// Creates the message.
  const DiceCommitMsg(this.commit);

  @override
  String get type => 'dice_commit';

  /// Commit.
  final DiceCommit commit;

  @override
  Map<String, Object?> toData() => commit.toJson();
}

/// Fair-dice reveal after a roll.
final class DiceRevealMsg extends ServerMessage {
  /// Creates the message.
  const DiceRevealMsg(this.reveal);

  @override
  String get type => 'dice_reveal';

  /// Reveal.
  final DiceReveal reveal;

  @override
  Map<String, Object?> toData() => reveal.toJson();
}

/// Rejected action, sent only to the sender.
final class ErrorMsg extends ServerMessage {
  /// Creates the message.
  const ErrorMsg(this.code, {this.message = '', this.refId});

  @override
  String get type => 'error';

  /// Reason code.
  final ErrorCode code;

  /// Extra detail.
  final String message;

  /// Id of the rejected message.
  final String? refId;

  @override
  Map<String, Object?> toData() => {
        'code': code.wire,
        if (message.isNotEmpty) 'message': message,
        if (refId != null) 'refId': refId,
      };
}

/// Someone sent an emote.
final class EmoteBroadcast extends ServerMessage {
  /// Creates the message.
  const EmoteBroadcast({required this.from, required this.emote});

  @override
  String get type => 'emote_shown';

  /// Sender.
  final String from;

  /// Emote.
  final Emote emote;

  @override
  Map<String, Object?> toData() => {'from': from, 'emote': emote.name};
}

/// Room notices: `paused`, `resumed`, `kicked`, `muted`, `saved`,
/// `rematch`, `pong`.
final class NoticeMsg extends ServerMessage {
  /// Creates the message.
  const NoticeMsg(this.kind, {this.text = '', this.data = const {}});

  @override
  String get type => 'notice';

  /// Notice kind.
  final String kind;

  /// Display text.
  final String text;

  /// Extra details.
  final Map<String, Object?> data;

  @override
  Map<String, Object?> toData() => {
        'kind': kind,
        if (text.isNotEmpty) 'text': text,
        if (data.isNotEmpty) 'data': data,
      };
}

/// Decoders for every data-carrying message type.
final Map<String, Message Function(Map<String, Object?>)> decoders = {
  'hello': Hello._decode,
  'ready': (d) => ReadyMsg(ready: d['ready'] as bool),
  'set_rules': (d) => SetRulesMsg(HouseRules.fromJson(d)),
  'add_bot': (d) => AddBotMsg(
      level: BotLevel.values.byName(d['level'] as String? ?? 'medium')),
  'kick': (d) => PlayerTargetMsg('kick', d['playerId'] as String),
  'mute_player': (d) => PlayerTargetMsg('mute_player', d['playerId'] as String,
      flag: d['muted'] as bool? ?? true),
  'bid': (d) => BidMsg(d['amount'] as int),
  for (final t in TileMsg.types) t: (d) => TileMsg(t, d['tile'] as int),
  'trade_propose': (d) => TradeProposeMsg(
        to: d['to'] as String,
        give: TradeSide.fromJson((d['give'] as Map).cast()),
        get: TradeSide.fromJson((d['get'] as Map).cast()),
      ),
  for (final t in TradeAnswerMsg.types)
    t: (d) => TradeAnswerMsg(t, d['tradeId'] as String),
  'trade_counter': (d) => TradeCounterMsg(
        d['tradeId'] as String,
        give: TradeSide.fromJson((d['give'] as Map).cast()),
        get: TradeSide.fromJson((d['get'] as Map).cast()),
      ),
  'emote': (d) => EmoteMsg(Emote.values.byName(d['emote'] as String)),
  'sync': (d) => SyncMsg(d['lastVersion'] as int),
  for (final t in SimpleIntent.types) t: (_) => SimpleIntent(t),
  'welcome': (d) => Welcome(
        playerId: d['playerId'] as String,
        sessionToken: d['sessionToken'] as String,
        state: GameState.fromJson((d['state'] as Map).cast()),
        password: d['password'] as bool? ?? false,
      ),
  'state': (d) => StateMsg(GameState.fromJson((d['state'] as Map).cast())),
  'patch': (d) => PatchMsg(
        fromVersion: d['fromVersion'] as int,
        toVersion: d['toVersion'] as int,
        changes: (d['changes'] as Map).cast(),
        events: [
          for (final e in (d['events'] as List? ?? const []))
            GameEvent.fromJson((e as Map).cast()),
        ],
      ),
  'dice_commit': (d) => DiceCommitMsg(DiceCommit.fromJson(d)),
  'dice_reveal': (d) => DiceRevealMsg(DiceReveal.fromJson(d)),
  'error': (d) => ErrorMsg(ErrorCode.fromWire(d['code'] as String),
      message: d['message'] as String? ?? '', refId: d['refId'] as String?),
  'emote_shown': (d) => EmoteBroadcast(
      from: d['from'] as String,
      emote: Emote.values.byName(d['emote'] as String)),
  'notice': (d) => NoticeMsg(d['kind'] as String,
      text: d['text'] as String? ?? '',
      data: d['data'] == null ? const {} : (d['data'] as Map).cast()),
};
