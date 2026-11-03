import 'package:collection/collection.dart';

const _deep = DeepCollectionEquality();

/// Value equality for models based on their JSON form.
///
/// Every model's `toJson` returns plain maps/lists/primitives, so comparing
/// the JSON trees gives deep structural equality.
mixin JsonEquality {
  /// JSON form of this value.
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
          _deep.equals(toJson(), (other as JsonEquality).toJson()));

  @override
  int get hashCode => _deep.hash(toJson());

  @override
  String toString() => '$runtimeType${toJson()}';
}

/// Reads a required int from [json].
int readInt(Map<String, Object?> json, String key) => json[key] as int;

/// Reads an optional int from [json] with a default.
int readIntOr(Map<String, Object?> json, String key, int fallback) =>
    (json[key] as int?) ?? fallback;

/// Reads a list of ints.
List<int> readIntList(Object? raw) =>
    raw == null ? const [] : List<int>.unmodifiable((raw as List).cast<int>());

/// Reads a list of strings.
List<String> readStringList(Object? raw) => raw == null
    ? const []
    : List<String>.unmodifiable((raw as List).cast<String>());

/// Reads a JSON object.
Map<String, Object?> readMap(Object? raw) =>
    (raw as Map).cast<String, Object?>();

/// Reads a list of JSON objects.
List<Map<String, Object?>> readMapList(Object? raw) => raw == null
    ? const []
    : (raw as List).map((e) => (e as Map).cast<String, Object?>()).toList();
