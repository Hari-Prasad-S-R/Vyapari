import 'dart:convert';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

void main() {
  test('India files load 40 tiles and 32 cards', () {
    final b = india();
    expect(b.tiles, hasLength(40));
    expect(b.cards, hasLength(32));
    expect(b.tiles.where((t) => t.type == TileType.city), hasLength(22));
    expect(b.tiles.where((t) => t.type == TileType.transport), hasLength(4));
    expect(b.tiles.where((t) => t.type == TileType.utility), hasLength(2));
    expect(b.config.startingCash, 1500000);
    expect(b.config.salary, 200000);
    expect(b.config.jailFine, 50000);
    final groups = <String, int>{};
    for (final t in b.tiles.where((t) => t.type == TileType.city)) {
      groups[t.group!] = (groups[t.group!] ?? 0) + 1;
    }
    expect(groups.values.toList(), [2, 3, 3, 3, 3, 3, 3, 2]);
  });

  Map<String, Object?> boardDoc() =>
      (jsonDecode(indiaJson().$1) as Map).cast<String, Object?>();

  test('missing tile is reported by name', () {
    final doc = boardDoc();
    (doc['tiles'] as List).removeAt(12);
    expect(
      () => BoardData.parse(jsonEncode(doc), indiaJson().$2),
      throwsA(isA<BoardValidationException>().having(
          (e) => e.problems,
          'problems',
          containsAll(
              ['expected 40 tiles, found 39', 'missing tile index 12']))),
    );
  });

  test('duplicate index is rejected', () {
    final doc = boardDoc();
    ((doc['tiles'] as List)[5] as Map)['index'] = 4;
    expect(
      () => BoardData.parse(jsonEncode(doc), indiaJson().$2),
      throwsA(isA<BoardValidationException>().having((e) => e.problems.join(),
          'problems', contains('duplicate tile index 4'))),
    );
  });

  test('unknown card effect is rejected', () {
    final doc = (jsonDecode(indiaJson().$2) as Map).cast<String, Object?>();
    (((doc['cards'] as List)[0] as Map)['effect'] as Map)['type'] = 'teleport';
    expect(
      () => BoardData.parse(indiaJson().$1, jsonEncode(doc)),
      throwsA(isA<BoardValidationException>()
          .having((e) => e.problems.join(), 'problems', contains('teleport'))),
    );
  });

  test('rupees format with Indian grouping', () {
    expect(formatRupees(1500000), '₹15,00,000');
    expect(formatRupees(150000), '₹1,50,000');
    expect(formatRupees(50000), '₹50,000');
    expect(formatRupees(999), '₹999');
    expect(formatRupees(0), '₹0');
    expect(formatRupees(200000000), '₹20,00,00,000');
    expect(formatRupees(-25000), '-₹25,000');
  });
}
