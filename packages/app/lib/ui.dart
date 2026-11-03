import 'package:flutter/material.dart';
import 'package:vyapari_core/vyapari_core.dart';

/// App version shown on Home.
const appVersion = '0.1.0';

/// Saffron brand colour.
const saffron = Color(0xFFFF8F00);

/// Light and dark themes.
ThemeData vyapariTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: saffron, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
  );
}

/// Layout size classes from `design.md` §8.
enum SizeClass { phone, medium, large }

/// Size class for a width.
SizeClass sizeClassOf(double width) => width < 600
    ? SizeClass.phone
    : width < 1024
        ? SizeClass.medium
        : SizeClass.large;

/// Emoji for each token.
String tokenEmoji(Token t) => switch (t) {
      Token.autoRickshaw => '🛺',
      Token.ambassador => '🚗',
      Token.elephant => '🐘',
      Token.cricketBat => '🏏',
      Token.kite => '🪁',
      Token.teaGlass => '🍵',
    };

/// Display name for each token.
String tokenName(Token t) => switch (t) {
      Token.autoRickshaw => 'Auto-rickshaw',
      Token.ambassador => 'Ambassador',
      Token.elephant => 'Elephant',
      Token.cricketBat => 'Cricket bat',
      Token.kite => 'Kite',
      Token.teaGlass => 'Tea glass',
    };

/// Distinct colours for player seats.
const seatColors = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFFFB8C00),
  Color(0xFF00897B),
  Color(0xFF6D4C41),
  Color(0xFFD81B60),
];

/// Colour for [playerId] in [s].
Color playerColor(GameState s, String? playerId) {
  final i = s.players.indexWhere((p) => p.id == playerId);
  return i < 0 ? Colors.grey : seatColors[i % seatColors.length];
}

/// Parses `#RRGGBB`.
Color hexColor(String? hex, [Color fallback = Colors.grey]) {
  if (hex == null || hex.length != 7) return fallback;
  return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
}

/// Animated rupee amount.
class CashText extends StatelessWidget {
  /// Creates the widget.
  const CashText(this.amount, {super.key, this.style});

  /// Amount.
  final int amount;

  /// Style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
        tween: IntTween(begin: amount, end: amount),
        duration: const Duration(milliseconds: 600),
        builder: (context, v, _) => Text(formatRupees(v), style: style),
      );
}
