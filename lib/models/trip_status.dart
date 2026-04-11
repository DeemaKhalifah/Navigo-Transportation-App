/// Values used for trip filtering and display.
abstract class TripStatus {
  static const all = 'all';
  static const scheduled = 'scheduled';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const onTrip = 'onTrip';

  static bool isValid(String? s) {
    return s == all ||
        s == scheduled ||
        s == completed ||
        s == cancelled ||
        s == onTrip;
  }

  /// Maps Firestore / legacy strings to canonical values.
  static String normalize(String? raw) {
    if (raw == null) return scheduled;

    final s = raw.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );

    if (s == 'all') return all;
    if (s == 'scheduled') return scheduled;
    if (s == 'completed') return completed;
    if (s == 'cancelled') return cancelled;
    if (s == 'ontrip') return onTrip;
    if (s == 'ongoing') return onTrip;
    if (s == 'inprogress') return onTrip;

    return scheduled;
  }

  static String label(String status) {
    switch (normalize(status)) {
      case scheduled:
        return 'Scheduled';
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      case onTrip:
        return 'On Trip';
      case all:
        return 'All';
      default:
        return 'Scheduled';
    }
  }
}
