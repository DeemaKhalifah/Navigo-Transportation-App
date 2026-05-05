import 'package:shared_preferences/shared_preferences.dart';

class PhoneLoginStorageService {
  static const String _rememberedPhoneKey = 'remembered_phone_number';
  static const String _rememberedRouteManagerEmailKey =
      'remembered_route_manager_email';

  Future<String?> getRememberedPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberedPhoneKey);
  }

  Future<void> saveRememberedPhoneNumber(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedPhoneKey, phoneNumber);
  }

  Future<void> clearRememberedPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberedPhoneKey);
  }

  Future<String?> getRememberedRouteManagerEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberedRouteManagerEmailKey);
  }

  Future<void> saveRememberedRouteManagerEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedRouteManagerEmailKey, email);
  }

  Future<void> clearRememberedRouteManagerEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberedRouteManagerEmailKey);
  }
}
