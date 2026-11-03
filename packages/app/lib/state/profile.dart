import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyapari_core/vyapari_core.dart';

/// A saved online server.
class SavedServer {
  /// Creates an entry.
  const SavedServer(this.name, this.url);

  /// Display name.
  final String name;

  /// WebSocket URL, e.g. `wss://vyapari.example.in/ws`.
  final String url;

  /// JSON form.
  Map<String, String> toJson() => {'name': name, 'url': url};
}

/// Nickname, token and saved servers (stored on the device; no login).
class Profile {
  /// Creates a profile.
  const Profile({
    this.name = '',
    this.token = Token.autoRickshaw,
    this.servers = const [],
    this.lastGroup = const [],
  });

  /// Nickname.
  final String name;

  /// Preferred token.
  final Token token;

  /// Saved online servers.
  final List<SavedServer> servers;

  /// Last private voice group (player names).
  final List<String> lastGroup;

  /// Copy with changes.
  Profile copyWith({
    String? name,
    Token? token,
    List<SavedServer>? servers,
    List<String>? lastGroup,
  }) =>
      Profile(
        name: name ?? this.name,
        token: token ?? this.token,
        servers: servers ?? this.servers,
        lastGroup: lastGroup ?? this.lastGroup,
      );
}

/// The device profile.
final profileProvider =
    NotifierProvider<ProfileController, Profile>(ProfileController.new);

/// Loads and saves the [Profile].
class ProfileController extends Notifier<Profile> {
  @override
  Profile build() {
    _load();
    return const Profile();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final servers = (jsonDecode(p.getString('servers') ?? '[]') as List)
          .map((e) => SavedServer(e['name'] as String, e['url'] as String))
          .toList();
      state = Profile(
        name: p.getString('name') ?? '',
        token: Token.values.asNameMap()[p.getString('token')] ??
            Token.autoRickshaw,
        servers: servers,
        lastGroup: p.getStringList('lastGroup') ?? const [],
      );
    } catch (_) {
      // First launch or storage unavailable: keep defaults.
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('name', state.name);
      await p.setString('token', state.token.name);
      await p.setString(
          'servers', jsonEncode([for (final s in state.servers) s.toJson()]));
      await p.setStringList('lastGroup', state.lastGroup);
    } catch (_) {}
  }

  /// Sets the nickname.
  void setName(String name) {
    state = state.copyWith(name: name.trim());
    _save();
  }

  /// Sets the token.
  void setToken(Token t) {
    state = state.copyWith(token: t);
    _save();
  }

  /// Adds or replaces a saved server.
  void addServer(SavedServer s) {
    state = state
        .copyWith(servers: [...state.servers.where((x) => x.url != s.url), s]);
    _save();
  }

  /// Removes a saved server.
  void removeServer(String url) {
    state = state.copyWith(
        servers: state.servers.where((x) => x.url != url).toList());
    _save();
  }

  /// Remembers the last voice group.
  void setLastGroup(List<String> ids) {
    state = state.copyWith(lastGroup: ids);
    _save();
  }
}
