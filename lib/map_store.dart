/// Keeps the map between launches.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'node_map.dart';

class MapStore {
  static const _key = 'mindmesh.map.v1';

  /// [aspect] shapes a fresh seed to the screen it will be shown on.
  Future<NodeMap> load({double aspect = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return NodeMap.seed(aspect: aspect);
    try {
      return NodeMap.fromJson(jsonDecode(raw), aspect: aspect);
    } on FormatException {
      // A map that will not parse is a map you no longer have; a seed is a
      // better answer than a launcher that refuses to draw.
      return NodeMap.seed(aspect: aspect);
    }
  }

  Future<void> save(NodeMap map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map.toJson()));
  }
}
