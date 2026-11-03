import 'package:vyapari_core/vyapari_core.dart';

import 'platform_api.dart';

export 'platform_api.dart';

/// Whether this platform can host a game (not on web).
bool get canHost => false;

/// Whether nearby discovery works here.
bool get canDiscover => false;

/// Whether the QR scanner is available.
bool get canScan => false;

/// Hosting is not available on web.
Future<LocalHostHandle> startLocalHost({
  required BoardData board,
  required String roomName,
  String? password,
}) =>
    throw UnsupportedError('Hosting is not available in the browser');

/// No LAN discovery on web.
Stream<List<NearbyHost>> discoverNearby() => const Stream.empty();

/// Browsers cannot inspect interfaces; assume online.
Future<bool> hasLocalNetwork() async => true;

/// Opens the hotspot settings (no-op on web).
Future<void> openHotspotSettings() async {}
