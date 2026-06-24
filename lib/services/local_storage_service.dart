import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_status.dart';

class LocalStorageService {
  static const String _selectedLineKey = 'selected_line';
  static const String _driverStatusKey = 'driver_status';
  static const String _driverDisplayNameKey = 'driver_display_name';

  static Future<void> saveSelectedLine(String line) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedLineKey, line);
  }

  static Future<String?> getSelectedLine() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedLineKey);
  }

  static Future<void> clearSelectedLine() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedLineKey);
  }

  static Future<void> saveDriverStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverStatusKey, DriverStatus.normalize(status));
  }

  static Future<String> getDriverStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return DriverStatus.normalize(prefs.getString(_driverStatusKey));
  }

  static Future<void> clearDriverStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_driverStatusKey);
  }

  static Future<void> saveDriverDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverDisplayNameKey, trimmed);
  }

  static Future<String?> getDriverDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_driverDisplayNameKey)?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  static Future<void> clearDriverDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_driverDisplayNameKey);
  }
}
