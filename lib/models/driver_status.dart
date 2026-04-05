/// Values stored in `drivers/{driverId}.status`
abstract class DriverStatus {
  static const offline = 'offline';
  static const available = 'available';
  static const onTrip = 'onTrip';

  static bool isValid(String? s) {
    return s == offline || s == available || s == onTrip;
  }

  /// Maps Firestore / legacy strings to [offline], [available], or [onTrip].
  static String normalize(String? raw) {
    if (raw == null) return offline;
    final s = raw.toString().trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    if (s == 'available') return available;
    if (s == 'ontrip') return onTrip;
    if (s == 'offline') return offline;
    return offline;
  }
}
