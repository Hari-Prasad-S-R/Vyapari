@Tags(['icons'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/widgets/logo.dart';

/// Regenerates the branding PNGs from the vector logo:
///   flutter test --tags icons --run-skipped test/generate_icons_test.dart
/// then run flutter_launcher_icons and flutter_native_splash (see README).
Future<void> _png(String name, int px, void Function(Canvas, Size) draw) async {
  final rec = ui.PictureRecorder();
  final size = Size.square(px.toDouble());
  draw(Canvas(rec, Offset.zero & size), size);
  final img = await rec.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File('assets/branding/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('generate branding PNGs', (tester) async {
    await tester.runAsync(() async {
      // iOS / web / legacy Android: full tile, no transparency, art at 78%.
      await _png('icon.png', 1024, (c, s) => paintRooftopV(c, s, art: 0.78));
      // Android adaptive foreground/monochrome: flutter_launcher_icons insets
      // these by 16%, so 0.88 here lands at ~0.6 of the icon, inside the 66%
      // safe zone every launcher mask keeps.
      await _png('icon_foreground.png', 1024,
          (c, s) => paintRooftopV(c, s, background: false, art: 0.88));
      // Android 13+ themed icon: one colour, the launcher tints it.
      await _png('icon_monochrome.png', 1024,
          (c, s) => paintRooftopV(c, s, art: 0.88, mono: Colors.white));
      // Web maskable icon: art inside the 80% safe circle.
      await _png(
          'icon_maskable.png', 512, (c, s) => paintRooftopV(c, s, art: 0.66));
      // Splash: transparent art (Android 12 crops it to a circle).
      await _png('splash.png', 768,
          (c, s) => paintRooftopV(c, s, background: false, art: 0.62));
    });
    for (final f in [
      'icon.png',
      'icon_foreground.png',
      'icon_monochrome.png',
      'icon_maskable.png',
      'splash.png'
    ]) {
      expect(File('assets/branding/$f').existsSync(), isTrue);
    }
  });
}
