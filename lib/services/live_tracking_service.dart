import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin Firestore stream proxy for real-time driver GPS location updates.
///
/// This is intentionally kept as a direct Firestore stream because
/// real-time GPS tracking requires sub-second latency that HTTP polling
/// cannot provide. No business logic — just streams location data.
class LiveTrackingService {
  final FirebaseFirestore _db;

  LiveTrackingService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Watch a driver's real-time location updates.
  /// Returns a stream of {lat, lng} maps.
  Stream<Map<String, double>?> watchDriverLocation(String driverId) {
    return _db
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;

      // Try top-level lat/lng first
      final lat = data['latitude'] as num?;
      final lng = data['longitude'] as num?;
      if (lat != null && lng != null) {
        return {'lat': lat.toDouble(), 'lng': lng.toDouble()};
      }

      // Try nested location object
      final loc = data['location'] as Map<String, dynamic>?;
      if (loc != null) {
        final locLat = loc['lat'] as num?;
        final locLng = loc['lng'] as num?;
        if (locLat != null && locLng != null) {
          return {'lat': locLat.toDouble(), 'lng': locLng.toDouble()};
        }
      }

      return null;
    });
  }

  /// Watch a driver's online/status changes.
  Stream<Map<String, dynamic>?> watchDriverStatus(String driverId) {
    return _db
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;

      return {
        'status': data['status'] ?? 'offline',
        'isOnline': data['isOnline'] ?? false,
      };
    });
  }
}
