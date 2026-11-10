import 'package:flutter/material.dart';
import 'package:vyapari_core/vyapari_core.dart';

/// App version shown on Home.
const appVersion = '0.2.1';

/// Marigold accent (buttons, highlights, logo).
const saffron = Color(0xFFF2A922);

/// Deep teal brand colour.
const brandTeal = Color(0xFF0B6E5F);

/// Light and dark themes: deep teal with marigold accents on warm cream
/// (light) or deep navy-green (dark).
ThemeData vyapariTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: brandTeal, brightness: b);
  final scheme = base.copyWith(
    primary: dark ? const Color(0xFF5FD4BC) : brandTeal,
    onPrimary: dark ? const Color(0xFF00382F) : Colors.white,
    secondary: saffron,
    onSecondary: const Color(0xFF2B1D00),
    secondaryContainer:
        dark ? const Color(0xFF1E4A43) : const Color(0xFFFFE3A8),
    onSecondaryContainer:
        dark ? const Color(0xFFD5F5EC) : const Color(0xFF2B1D00),
    surface: dark ? const Color(0xFF0E1A1C) : const Color(0xFFFFF8EC),
    surfaceContainer: dark ? const Color(0xFF152528) : const Color(0xFFF7EEDD),
    surfaceContainerHigh:
        dark ? const Color(0xFF1B2E31) : const Color(0xFFF1E6D2),
    surfaceContainerHighest:
        dark ? const Color(0xFF22383B) : const Color(0xFFEBDDC6),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF152528) : brandTeal,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: scheme.surfaceContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
            shape: shape,
            textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 48), shape: shape)),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: saffron, foregroundColor: Color(0xFF2B1D00)),
    chipTheme: ChipThemeData(shape: shape),
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
