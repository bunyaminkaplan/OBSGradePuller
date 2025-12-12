import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  // Legacy Keys
  static const _keyUserLegacy = 'obs_username';
  static const _keyPassLegacy = 'obs_password';

  // New Key
  static const _keyProfiles = 'obs_profiles';

  /// Returns list of stored profiles: [{'username': '...', 'password': '...', 'alias': '...'}]
  Future<List<Map<String, String>>> getProfiles() async {
    // 1. Check for legacy data and migrate
    await _migrateLegacyData();

    // 2. Read profiles
    String? jsonStr = await _storage.read(key: _keyProfiles);
    if (jsonStr == null) return [];

    try {
      List<dynamic> list = jsonDecode(jsonStr);
      return list.map((e) => Map<String, String>.from(e)).toList();
    } catch (e) {
      print("Storage Error: $e");
      return [];
    }
  }

  Future<void> saveProfile(
    String username,
    String password,
    String alias,
  ) async {
    List<Map<String, String>> profiles = await getProfiles();

    // Remove existing if any (update mode)
    profiles.removeWhere((p) => p['username'] == username);

    // Add new
    profiles.add({'username': username, 'password': password, 'alias': alias});

    await _storage.write(key: _keyProfiles, value: jsonEncode(profiles));
  }

  Future<void> removeProfile(String username) async {
    List<Map<String, String>> profiles = await getProfiles();
    profiles.removeWhere((p) => p['username'] == username);
    await _storage.write(key: _keyProfiles, value: jsonEncode(profiles));
  }

  Future<void> _migrateLegacyData() async {
    String? oldUser = await _storage.read(key: _keyUserLegacy);
    String? oldPass = await _storage.read(key: _keyPassLegacy);

    if (oldUser != null && oldPass != null) {
      print("Migrating legacy user: $oldUser");
      // Read existing profiles directly to avoid loop
      String? jsonStr = await _storage.read(key: _keyProfiles);
      List<dynamic> list = jsonStr != null ? jsonDecode(jsonStr) : [];
      List<Map<String, String>> profiles = list
          .map((e) => Map<String, String>.from(e))
          .toList();

      // check if already exists
      if (!profiles.any((p) => p['username'] == oldUser)) {
        profiles.add({
          'username': oldUser,
          'password': oldPass,
          'alias': 'Varsayılan', // Default alias
        });
        await _storage.write(key: _keyProfiles, value: jsonEncode(profiles));
      }

      // Delete legacy
      await _storage.delete(key: _keyUserLegacy);
      await _storage.delete(key: _keyPassLegacy);
    }
  }

  // Backwards compatibility helper (optional, can remove if unused)
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
