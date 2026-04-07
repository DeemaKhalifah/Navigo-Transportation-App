import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _selectedLineKey = 'selected_line';

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
}
