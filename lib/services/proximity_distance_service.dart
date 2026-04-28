import 'package:geolocator/geolocator.dart';

class ProximityDistanceService {
  const ProximityDistanceService();

  double? calculateMeters({
    required double? driverLat,
    required double? driverLng,
    required double? passengerLat,
    required double? passengerLng,
  }) {
    if (driverLat == null ||
        driverLng == null ||
        passengerLat == null ||
        passengerLng == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      driverLat,
      driverLng,
      passengerLat,
      passengerLng,
    );
  }

  bool isWithinRadius({
    required double? driverLat,
    required double? driverLng,
    required double? passengerLat,
    required double? passengerLng,
    double radiusMeters = 500,
  }) {
    final meters = calculateMeters(
      driverLat: driverLat,
      driverLng: driverLng,
      passengerLat: passengerLat,
      passengerLng: passengerLng,
    );

    if (meters == null) return false;
    return meters <= radiusMeters;
  }
}
