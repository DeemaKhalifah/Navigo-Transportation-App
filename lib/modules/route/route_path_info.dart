import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RoutePathInfo {
  const RoutePathInfo({
    required this.startLocation,
    required this.endLocation,
    required this.path,
    required this.etaMinutes,
    required this.etaText,
    required this.distanceMeters,
    required this.distanceText,
    required this.encodedPolyline,
    required this.provider,
  });

  final LatLng startLocation;
  final LatLng endLocation;
  final List<LatLng> path;
  final int etaMinutes;
  final String etaText;
  final int distanceMeters;
  final String distanceText;
  final String encodedPolyline;
  final String provider;

  double get distanceKm => distanceMeters / 1000;

  Map<String, dynamic> toRouteModuleMap() {
    return {
      'etaMinutes': etaMinutes,
      'etaText': etaText,
      'distanceMeters': distanceMeters,
      'distanceKm': distanceKm,
      'distanceText': distanceText,
      'startLocation': {
        'lat': startLocation.latitude,
        'lng': startLocation.longitude,
      },
      'endLocation': {
        'lat': endLocation.latitude,
        'lng': endLocation.longitude,
      },
      'provider': provider,
      'updatedAt': Timestamp.now(),
    };
  }

  Map<String, dynamic> toFirestoreRouteMap() {
    return {
      'startLocation': {
        'lat': startLocation.latitude,
        'lng': startLocation.longitude,
      },
      'endLocation': {
        'lat': endLocation.latitude,
        'lng': endLocation.longitude,
      },
      'polyline': encodedPolyline,
      'routePolyline': encodedPolyline,
      'etaMinutes': etaMinutes,
      'etaText': etaText,
      'estimatedTime': etaMinutes,
      'distanceMeters': distanceMeters,
      'distanceKm': distanceKm,
      'distanceText': distanceText,
      'routeModule': toRouteModuleMap(),
      'routePathProvider': provider,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

